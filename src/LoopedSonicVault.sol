// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 *
 *  LoopedSonicVault – ERC20 Vault Token with Flash‑Accounting Execution Flow (OpenZeppelin‑based)
 *  -----------------------------------------------------------------------------------
 *  ▸ Issues ERC20 vault shares (inherits OpenZeppelin ERC20)
 *  ▸ Supports WETH + wstETH as managed assets
 *  ▸ Provides modular primitives (stake/borrow/repay/etc.) callable only inside an
 *    atomic flash‑loan‑style callback ("operation mode")
 *  ▸ Integrates with Lido for staking and Aave for lending/borrowing on Arbitrum
 *  ▸ Enforces robust invariants (Aave HF ≥ 1, no share‑price decrease, etc.)
 *
 */
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISonicStaking} from "./interfaces/ISonicStaking.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AaveAccount} from "./libraries/AaveAccount.sol";
import {AaveAccountComparison} from "./libraries/AaveAccountComparison.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ILoopedSonicVault} from "./interfaces/ILoopedSonicVault.sol";
import {console} from "forge-std/console.sol";

/**
 * @title LoopedSonicVault
 * @notice Vault that lets users create a leveraged wstETH position on Aave via an atomic, flash‑loan‑style callback.
 *         Vault shares are ERC20 and track a proportional claim on net asset value (ETH terms).
 */
contract LoopedSonicVault is ERC20, AccessControl, ReentrancyGuard, ILoopedSonicVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using AaveAccount for AaveAccount.Data;
    using AaveAccountComparison for AaveAccountComparison.Data;

    bytes32 public constant DONATOR_ROLE = keccak256("DONATOR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant VARIABLE_INTEREST_RATE = 2;
    uint256 public constant MIN_LST_DEPOSIT = 0.01e18; // 0.01
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.01e18; // 0.01
    uint256 public constant MIN_UNWIND_AMOUNT = 0.01e18; // 0.01
    uint256 public constant MAX_UNWIND_SLIPPAGE = 0.02e18; // 2%
    uint256 public constant MIN_NAV_INCREASE_ETH = 0.01e18; // 0.01 ETH
    uint256 public constant MIN_TARGET_HEALTH_FACTOR = 1.1e18; // 1.1
    uint256 public constant MIN_SHARES_TO_REDEEM = 0.01e18; // 0.01
    uint256 public constant INIT_AMOUNT = 1e18; // 1 ETH

    // ---------------------------------------------------------------------
    // External protocol references (immutable after deployment)
    // ---------------------------------------------------------------------
    IWETH public immutable WETH;
    ISonicStaking public immutable LST;
    IAavePool public immutable AAVE_POOL;

    bool public isInitialized = false;

    uint256 public targetHealthFactor = 1.3e18;
    uint256 public allowedUnwindSlippage = 0.007e18; // 0.7%

    bool public depositsPaused = false;
    bool public withdrawsPaused = false;
    bool public donationsPaused = false;
    bool public unwindsPaused = false;

    // ---------------------------------------------------------------------
    // Flash‑accounting operation state (transient; zeroed every execution)
    // ---------------------------------------------------------------------
    bool private transient locked;
    address private transient allowedCaller;
    uint256 private transient _wethSessionBalance;
    uint256 private transient _lstSessionBalance;

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    constructor(address _weth, address _lst, address _aavePool, address _admin)
        ERC20("Beets Aave Looped Sonic", "lS")
    {
        require(_weth != address(0) && _lst != address(0) && _aavePool != address(0), ZeroAddress());

        WETH = IWETH(_weth);
        LST = ISonicStaking(_lst);
        AAVE_POOL = IAavePool(_aavePool);

        // Approve Aave once for both tokens
        IERC20(_weth).approve(_aavePool, type(uint256).max);
        IERC20(_lst).approve(_aavePool, type(uint256).max);

        // Grant admin role to admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyWhenLocked() {
        require(locked, NotLocked());
        require(msg.sender == allowedCaller, NotAllowed());

        _;
    }

    modifier onlyWhenNotLocked() {
        require(!locked, Locked());
        _;
    }

    modifier acquireLock() {
        require(!locked, Locked());

        locked = true;
        allowedCaller = msg.sender;

        _;

        // You must clear your session balance by the end of any operation that acquires a lock
        require(_wethSessionBalance == 0, WETHSessionBalanceNotZero());
        require(_lstSessionBalance == 0, LSTSessionBalanceNotZero());

        locked = false;
        allowedCaller = address(0);
    }

    modifier whenInitialized() {
        require(isInitialized, NotInitialized());
        _;
    }

    // ---------------------------------------------------------------------
    // Primary vault operations, each function acquires a lock and then executes a callback, strictly enforcing
    // invariants after the callback.
    // ---------------------------------------------------------------------

    /**
     * @param callbackData Arbitrary calldata forwarded to the callback.
     */
    function deposit(address receiver, bytes calldata callbackData) external nonReentrant whenInitialized acquireLock {
        require(!depositsPaused, DepositsPaused());

        AaveAccountComparison.Data memory data;
        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();

        // -------------------- Pre‑state snapshot -------------------------
        data.accountBefore = _loadAaveAccountData(ethPrice, lstPrice);

        // We execute the callback, giving control back to the caller to perform the deposit
        (msg.sender).functionCall(callbackData);

        // -------------------- Post checks -------------------------------

        data.accountAfter = _loadAaveAccountData(ethPrice, lstPrice);
        uint256 navIncreaseEth = data.navIncreaseEth();

        require(navIncreaseEth >= MIN_NAV_INCREASE_ETH, NavIncreaseBelowMin());

        require(data.checkHealthFactorAfterDeposit(targetHealthFactor), HealthFactorNotInRange());

        // we issue shares such that the invariant of totalAssets / totalSupply is preserved, rounding down
        uint256 shares = totalSupply() * data.navIncreaseBase() / data.accountBefore.netAssetValueBase();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, shares, navIncreaseEth);
    }

    /**
     * @param sharesToRedeem Amount of vault shares to burn.
     * @param callbackData          Arbitrary calldata forwarded to the callback.
     */
    function withdraw(uint256 sharesToRedeem, bytes calldata callbackData)
        external
        nonReentrant
        whenInitialized
        acquireLock
    {
        require(!withdrawsPaused, WithdrawsPaused());
        require(sharesToRedeem > MIN_SHARES_TO_REDEEM, NotEnoughShares());

        AaveAccountComparison.Data memory data;
        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();

        // -------------------- Pre‑state snapshot -------------------------
        data.accountBefore = _loadAaveAccountData(ethPrice, lstPrice);
        uint256 totalSupplyBefore = totalSupply();

        // Burn shares up‑front for withdrawals
        // The caller must have the shares, this is an additional erc20 transfer, but avoids a second layer of
        // of permissions
        _burn(msg.sender, sharesToRedeem);

        // ----------------------- Callback -------------------------------
        (msg.sender).functionCall(callbackData);

        // -------------------- Post checks -------------------------------

        data.accountAfter = _loadAaveAccountData(ethPrice, lstPrice);

        require(data.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore), InvalidDebtAfterWithdraw());
        require(data.checkCollateralAfterWithdraw(sharesToRedeem, totalSupplyBefore), InvalidCollateralAfterWithdraw());
        require(data.checkNavAfterWithdraw(sharesToRedeem, totalSupplyBefore), InvalidNavAfterWithdraw());

        emit Withdraw(msg.sender, sharesToRedeem, data.navDecreaseEth());
    }

    function initialize() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) acquireLock {
        require(!isInitialized, AlreadyInitialized());

        pullWeth(INIT_AMOUNT);

        stakeWeth(INIT_AMOUNT);

        aaveSupplyLst(_lstSessionBalance);

        AAVE_POOL.setUserEMode(1);
        AAVE_POOL.setUserUseReserveAsCollateral(address(LST), true);

        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();
        AaveAccount.Data memory aaveAccount = _loadAaveAccountData(ethPrice, lstPrice);

        require(aaveAccount.totalDebtBase == 0, DebtNotZero());

        // Since the vault's nav was 0 before initialization, the amount of shares to mint is the nav, valued in ETH
        uint256 sharesToMint = aaveAccount.netAssetValueInEth();

        // We burn the initial shares so that the total supply will never return to 0
        // We use address(1) since openzeppelin's ERC20 does not allow minting to the zero address
        _mint(address(1), sharesToMint);

        isInitialized = true;

        emit Initialize(msg.sender, address(1), sharesToMint, sharesToMint);
    }

    function unwind(uint256 lstAmountToWithdraw, address contractToCall, bytes calldata data)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
        whenInitialized
        acquireLock
    {
        require(!unwindsPaused, UnwindsPaused());
        require(lstAmountToWithdraw > MIN_UNWIND_AMOUNT, UnwindAmountBelowMin());

        aaveWithdrawLst(lstAmountToWithdraw);

        sendLst(msg.sender, lstAmountToWithdraw);

        // The redemption amount is the true value of the collateral, in ETH terms. It is the amount of WETH that
        // we would receive from doing the time based redemption of the LST.
        uint256 redemptionAmount = _lstToEth(lstAmountToWithdraw);

        // Disallow msg.sender from calling into the vault during the scope of the callback
        allowedCaller = address(0);

        // The callback will sell the LST and return the amount of WETH received.
        bytes memory result = (contractToCall).functionCall(data);
        uint256 wethAmount = abi.decode(result, (uint256));

        allowedCaller = msg.sender;

        require(wethAmount >= redemptionAmount * (1e18 - allowedUnwindSlippage) / 1e18, NotEnoughWETH());

        pullWeth(wethAmount);

        aaveRepayWeth(wethAmount);

        emit Unwind(msg.sender, lstAmountToWithdraw, wethAmount);
    }

    function donate(uint256 wethAmount, uint256 lstAmount)
        external
        nonReentrant
        onlyRole(DONATOR_ROLE)
        whenInitialized
        acquireLock
    {
        require(!donationsPaused, DonationsPaused());
        require(wethAmount > 0 || lstAmount > 0, ZeroAmount());

        if (wethAmount > 0) {
            pullWeth(wethAmount);
            stakeWeth(wethAmount);
        }

        if (lstAmount > 0) {
            pullLst(lstAmount);
        }

        uint256 totalAmountDonatedEth = _lstToEth(_lstSessionBalance);

        // We only supply the LST to the Aave pool, we leave the task of looping to the next deposit
        aaveSupplyLst(_lstSessionBalance);

        emit Donate(msg.sender, totalAmountDonatedEth, wethAmount, lstAmount);
    }

    // ---------------------------------------------------------------------
    // Vault primitives (ONLY callable during an active lock)
    // ---------------------------------------------------------------------

    function stakeWeth(uint256 amount) public onlyWhenLocked returns (uint256 lstAmount) {
        require(amount >= MIN_LST_DEPOSIT, AmountLessThanMin());

        _decrementWethSessionBalance(amount);

        // the LST only accepts native ETH, so we unwrap WETH prior to calling deposit
        WETH.withdraw(amount);

        lstAmount = LST.deposit{value: amount}();

        _incrementLstSessionBalance(lstAmount);

        emit StakeWeth(allowedCaller, amount, lstAmount);
    }

    function aaveSupplyLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        _decrementLstSessionBalance(amount);

        AAVE_POOL.supply(address(LST), amount, address(this), 0);

        emit AaveSupplyLst(allowedCaller, amount);
    }

    function aaveWithdrawLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        AAVE_POOL.withdraw(address(LST), amount, address(this));

        _incrementLstSessionBalance(amount);

        emit AaveWithdrawLst(allowedCaller, amount);
    }

    function aaveBorrowWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        AAVE_POOL.borrow(address(WETH), amount, VARIABLE_INTEREST_RATE, 0, address(this));

        _incrementWethSessionBalance(amount);

        emit AaveBorrowWeth(allowedCaller, amount);
    }

    function aaveRepayWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        _decrementWethSessionBalance(amount);

        AAVE_POOL.repay(address(WETH), amount, VARIABLE_INTEREST_RATE, address(this));

        emit AaveRepayWeth(allowedCaller, amount);
    }

    function sendWeth(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());
        require(to != address(0), ZeroAddress());

        IERC20(address(WETH)).safeTransfer(to, amount);

        _decrementWethSessionBalance(amount);

        emit SendWeth(allowedCaller, to, amount);
    }

    function sendLst(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());
        require(to != address(0), ZeroAddress());

        IERC20(address(LST)).safeTransfer(to, amount);

        _decrementLstSessionBalance(amount);

        emit SendLst(allowedCaller, to, amount);
    }

    function pullWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementWethSessionBalance(amount);

        emit PullWeth(allowedCaller, msg.sender, amount);
    }

    function pullLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, ZeroAmount());

        IERC20(address(LST)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementLstSessionBalance(amount);

        emit PullLst(allowedCaller, msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    function getAssetPrices() public view returns (uint256 ethPrice, uint256 lstPrice) {
        IPriceOracle aaveOracle = AAVE_POOL.ADDRESSES_PROVIDER().getPriceOracle();

        ethPrice = aaveOracle.getAssetPrice(address(WETH));
        lstPrice = aaveOracle.getAssetPrice(address(LST));
    }

    function getVaultAaveAccountData() public view returns (AaveAccount.Data memory) {
        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();
        return _loadAaveAccountData(ethPrice, lstPrice);
    }

    function totalAssets() public view onlyWhenNotLocked returns (uint256) {
        return getVaultAaveAccountData().netAssetValueInEth();
    }

    function convertToAssets(uint256 shares) public view onlyWhenNotLocked returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 totalShares = totalSupply();

        if (assetsTotal == 0 || totalShares == 0) {
            return shares;
        }

        return (shares * assetsTotal) / totalShares;
    }

    function convertToShares(uint256 assets) public view onlyWhenNotLocked returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 totalShares = totalSupply();

        if (assetsTotal == 0 || totalShares == 0) {
            return assets;
        }

        return (assets * totalShares) / assetsTotal;
    }

    function getRate() public view onlyWhenNotLocked returns (uint256) {
        // The rate is the amount of assets that 1 share is worth
        return convertToAssets(1 ether);
    }

    function getCollateralAndDebtForShares(uint256 shares)
        public
        view
        onlyWhenNotLocked
        returns (uint256 collateralInLst, uint256 debtInEth)
    {
        uint256 totalSupply = totalSupply();

        require(shares > 0, ZeroShares());
        require(shares <= totalSupply, SharesExceedTotalSupply());

        AaveAccount.Data memory aaveAccount = getVaultAaveAccountData();
        collateralInLst = aaveAccount.proportionalCollateralInLst(shares, totalSupply);
        debtInEth = aaveAccount.proportionalDebtInEth(shares, totalSupply);
    }

    // ---------------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------------

    function setTargetHealthFactor(uint256 _targetHealthFactor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_targetHealthFactor >= MIN_TARGET_HEALTH_FACTOR, TargetHealthFactorTooLow());
        targetHealthFactor = _targetHealthFactor;
    }

    function setAllowedUnwindSlippage(uint256 _allowedUnwindSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_allowedUnwindSlippage <= MAX_UNWIND_SLIPPAGE, SlippageTooHigh());
        allowedUnwindSlippage = _allowedUnwindSlippage;
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _setDepositsPaused(true);
        _setWithdrawsPaused(true);
        _setDonationsPaused(true);
        _setUnwindsPaused(true);
    }

    function setDepositsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDepositsPaused(_paused);
    }

    function setWithdrawsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setWithdrawsPaused(_paused);
    }

    function setDonationsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDonationsPaused(_paused);
    }

    function setUnwindsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUnwindsPaused(_paused);
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _lstToEth(uint256 lstAmount) private view returns (uint256) {
        return LST.convertToAssets(lstAmount);
    }

    function _setDepositsPaused(bool _paused) internal {
        if (depositsPaused != _paused) {
            depositsPaused = _paused;
            emit DepositsPausedChanged(_paused);
        }
    }

    function _setWithdrawsPaused(bool _paused) internal {
        if (withdrawsPaused != _paused) {
            withdrawsPaused = _paused;
            emit WithdrawsPausedChanged(_paused);
        }
    }

    function _setDonationsPaused(bool _paused) internal {
        if (donationsPaused != _paused) {
            donationsPaused = _paused;
            emit DonationsPausedChanged(_paused);
        }
    }

    function _setUnwindsPaused(bool _paused) internal {
        if (unwindsPaused != _paused) {
            unwindsPaused = _paused;
            emit UnwindsPausedChanged(_paused);
        }
    }

    function _incrementWethSessionBalance(uint256 amount) private {
        _wethSessionBalance += amount;
    }

    function _incrementLstSessionBalance(uint256 amount) private {
        _lstSessionBalance += amount;
    }

    function _decrementWethSessionBalance(uint256 amount) private {
        require(_wethSessionBalance >= amount, InsufficientWETHSessionBalance());

        _wethSessionBalance -= amount;
    }

    function _decrementLstSessionBalance(uint256 amount) private {
        require(_lstSessionBalance >= amount, InsufficientLSTSessionBalance());

        _lstSessionBalance -= amount;
    }

    function _loadAaveAccountData(uint256 ethPrice, uint256 lstPrice)
        private
        view
        returns (AaveAccount.Data memory aaveAccount)
    {
        aaveAccount.initialize(AAVE_POOL, address(this), ethPrice, lstPrice);
    }

    receive() external payable {
        // Only accept ETH from the WETH contract. The vault calls WETH.withdraw to unwrap WETH before
        // calling stake on the LST contract.
        require(msg.sender == address(WETH), SenderNotWethContract());
    }
}
