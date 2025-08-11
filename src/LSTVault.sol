// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 *
 *  LSTVault – ERC20 Vault Token with Flash‑Accounting Execution Flow (OpenZeppelin‑based)
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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISonicStaking} from "./interfaces/ISonicStaking.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AaveAccount} from "./libraries/AaveAccount.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {console} from "forge-std/console.sol";

/**
 * @title LSTVault
 * @notice Vault that lets users create a leveraged wstETH position on Aave via an atomic, flash‑loan‑style callback.
 *         Vault shares are ERC20 and track a proportional claim on net asset value (ETH terms).
 */
contract LSTVault is ERC20, Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using AaveAccount for AaveAccount.Data;

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
    constructor(address _weth, address _lst, address _aavePool, address _owner)
        ERC20("LST Vault Share", "LSTV")
        Ownable(_owner)
    {
        require(_weth != address(0) && _lst != address(0) && _aavePool != address(0), "Zero addr");

        WETH = IWETH(_weth);
        LST = ISonicStaking(_lst);
        AAVE_POOL = IAavePool(_aavePool);

        // Approve Aave once for both tokens (safe since Aave pool is trusted)
        IERC20(_weth).approve(_aavePool, type(uint256).max);
        IERC20(_lst).approve(_aavePool, type(uint256).max);

        // Grant admin role to owner
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyWhenLocked() {
        require(locked, "Not locked");
        require(msg.sender == allowedCaller, "Not allowed");

        _;
    }

    modifier onlyWhenNotLocked() {
        require(!locked, "Locked");
        _;
    }

    modifier acquireLock() {
        require(!locked, "Op in progress");

        locked = true;
        allowedCaller = msg.sender;

        _;

        // You must clear your session balance by the end of any operation that acquires a lock
        require(_wethSessionBalance == 0, "WETH session balance != 0");
        require(_lstSessionBalance == 0, "LST session balance != 0");

        locked = false;
        allowedCaller = address(0);
    }

    modifier whenInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    // ---------------------------------------------------------------------
    // Primary vault operations, each function acquires a lock and then executes a callback, strictly enforcing
    // invariants after the callback.
    // ---------------------------------------------------------------------

    /**
     * @param data Arbitrary calldata forwarded to the callback.
     */
    function deposit(address receiver, bytes calldata data) external nonReentrant whenInitialized acquireLock {
        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();

        // -------------------- Pre‑state snapshot -------------------------
        AaveAccount.Data memory aaveAccountBefore = _loadAaveAccountData(ethPrice, lstPrice);

        uint256 navBeforeEth = aaveAccountBefore.netAssetValueInEth();

        // We execute the callback, giving control back to the caller to perform the deposit
        (msg.sender).functionCall(data);

        // -------------------- Post checks -------------------------------

        AaveAccount.Data memory aaveAccountAfter = _loadAaveAccountData(ethPrice, lstPrice);
        uint256 navAfterEth = aaveAccountAfter.netAssetValueInEth();

        uint256 navIncreaseEth = navAfterEth - navBeforeEth;

        require(navIncreaseEth >= MIN_NAV_INCREASE_ETH, "Net change < min");

        // TODO: investigate what is the best margin to use here
        if (aaveAccountBefore.healthFactor < targetHealthFactor) {
            // The current health factor is below the target, so we require that the health factor cannot decrease
            // from it's current value
            require(aaveAccountAfter.healthFactor >= aaveAccountBefore.healthFactor * 0.999e18 / 1e18, "HF < target");
        } else {
            // The current health factor is above the target, so we require that the health factor stays above the
            // target
            //TODO: health factor should be greater than target but less than a margin
            require(aaveAccountAfter.healthFactor >= targetHealthFactor * 0.999e18 / 1e18, "HF < target");
        }

        // we issue shares such that the invariant of totalAssets / totalSupply is preserved, rounding down
        uint256 shares = totalSupply() * navIncreaseEth / navBeforeEth;

        _mint(receiver, shares);
    }

    /**
     * @param sharesToRedeem Amount of vault shares to burn.
     * @param data          Arbitrary calldata forwarded to the callback.
     */
    function withdraw(uint256 sharesToRedeem, bytes calldata data) external nonReentrant whenInitialized acquireLock {
        require(sharesToRedeem > MIN_SHARES_TO_REDEEM, "Not enough shares");

        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();

        // -------------------- Pre‑state snapshot -------------------------

        AaveAccount.Data memory aaveAccountBefore = _loadAaveAccountData(ethPrice, lstPrice);
        uint256 navBefore = aaveAccountBefore.netAssetValueBase();
        uint256 totalSupplyBefore = totalSupply();

        uint256 navForShares = navBefore * sharesToRedeem / totalSupplyBefore;

        uint256 expectedDebtAfter =
            aaveAccountBefore.totalDebtBase - aaveAccountBefore.proportionalDebtBase(sharesToRedeem, totalSupplyBefore);
        uint256 expectedCollateralAfter = aaveAccountBefore.totalCollateralBase
            - aaveAccountBefore.proportionalCollateralBase(sharesToRedeem, totalSupplyBefore);
        uint256 expectedNavAfter = navBefore - navForShares;

        // Burn shares up‑front for withdrawals
        // The caller must have the shares, this is an additional erc20 transfer, but avoids a second layer of
        // of permissions
        _burn(msg.sender, sharesToRedeem);

        // ----------------------- Callback -------------------------------
        (msg.sender).functionCall(data);

        // -------------------- Post checks -------------------------------

        AaveAccount.Data memory aaveAccountAfter = _loadAaveAccountData(ethPrice, lstPrice);
        uint256 navAfter = aaveAccountAfter.netAssetValueBase();

        // TODO: investigate what is the best margin to use here
        require(expectedDebtAfter == aaveAccountAfter.totalDebtBase, "Debt != expected");
        require(expectedCollateralAfter == aaveAccountAfter.totalCollateralBase, "Collateral != expected");
        require(navAfter == expectedNavAfter, "Nav != expected");
    }

    function initialize() external nonReentrant onlyOwner acquireLock {
        require(!isInitialized, "Already initialized");

        pullWeth(INIT_AMOUNT);

        stakeWeth(INIT_AMOUNT);

        aaveSupplyLst(_lstSessionBalance);

        AAVE_POOL.setUserEMode(1);
        AAVE_POOL.setUserUseReserveAsCollateral(address(LST), true);

        (uint256 ethPrice, uint256 lstPrice) = getAssetPrices();
        AaveAccount.Data memory aaveAccount = _loadAaveAccountData(ethPrice, lstPrice);

        require(aaveAccount.totalDebtBase == 0, "Debt != 0");

        // Since the vault's nav was 0 before initialization, the amount of shares to mint is the nav
        uint256 sharesToMint = aaveAccount.netAssetValueInEth();

        // TODO: revisit this, ideally this is the zero address
        // we burn the initial shares so that the total supply will never return to 0
        _mint(address(1), sharesToMint);

        isInitialized = true;
    }

    function unwind(uint256 lstAmountToWithdraw, bytes calldata data)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
        whenInitialized
        acquireLock
    {
        require(lstAmountToWithdraw > MIN_UNWIND_AMOUNT, "Unwind amount < min");

        aaveWithdrawLst(lstAmountToWithdraw);

        sendLst(msg.sender, lstAmountToWithdraw);

        // The redemption amount is the true value of the collateral, in ETH terms. It is the amount of WETH that
        // we would receive from doing the time based redemption of the LST.
        uint256 redemptionAmount = _lstToEth(lstAmountToWithdraw);

        // Disallow msg.sender from calling into the vault during the scope of the callback
        allowedCaller = address(0);

        // The callback will sell the LST and return the amount of WETH received.
        bytes memory result = (msg.sender).functionCall(data);
        uint256 wethAmount = abi.decode(result, (uint256));

        allowedCaller = msg.sender;

        require(wethAmount >= redemptionAmount * (1e18 - allowedUnwindSlippage) / 1e18, "Not enough WETH");

        pullWeth(wethAmount);

        aaveRepayWeth(wethAmount);
    }

    function donate(uint256 wethAmount, uint256 lstAmount) external nonReentrant onlyRole(DONATOR_ROLE) acquireLock {
        pullWeth(wethAmount);
        pullLst(lstAmount);

        stakeWeth(wethAmount);

        // We only supply the LST to the Aave pool, we leave the task of looping to the next deposit
        aaveSupplyLst(_lstSessionBalance);
    }

    // ---------------------------------------------------------------------
    // Vault primitives (ONLY callable during an active lock)
    // ---------------------------------------------------------------------

    function stakeWeth(uint256 amount) public onlyWhenLocked returns (uint256 lstAmount) {
        require(amount >= MIN_LST_DEPOSIT, "Not enough WETH");

        _decrementWethSessionBalance(amount);

        // the LST only accepts native ETH, so we unwrap WETH prior to calling deposit
        WETH.withdraw(amount);

        lstAmount = LST.deposit{value: amount}();

        _incrementLstSessionBalance(lstAmount);
    }

    function aaveSupplyLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        _decrementLstSessionBalance(amount);

        AAVE_POOL.supply(address(LST), amount, address(this), 0);
    }

    function aaveWithdrawLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        AAVE_POOL.withdraw(address(LST), amount, address(this));

        _incrementLstSessionBalance(amount);
    }

    function aaveBorrowWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        AAVE_POOL.borrow(address(WETH), amount, VARIABLE_INTEREST_RATE, 0, address(this));

        _incrementWethSessionBalance(amount);
    }

    function aaveRepayWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        _decrementWethSessionBalance(amount);

        AAVE_POOL.repay(address(WETH), amount, VARIABLE_INTEREST_RATE, address(this));
    }

    function sendWeth(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0 && to != address(0), "Bad args");

        IERC20(address(WETH)).safeTransfer(to, amount);

        _decrementWethSessionBalance(amount);
    }

    function sendLst(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0 && to != address(0), "Bad args");

        IERC20(address(LST)).safeTransfer(to, amount);

        _decrementLstSessionBalance(amount);
    }

    function pullWeth(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementWethSessionBalance(amount);
    }

    function pullLst(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        IERC20(address(LST)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementLstSessionBalance(amount);
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

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _lstToEth(uint256 lstAmount) private view returns (uint256) {
        return LST.convertToAssets(lstAmount);
    }

    function _incrementWethSessionBalance(uint256 amount) private {
        _wethSessionBalance += amount;
    }

    function _incrementLstSessionBalance(uint256 amount) private {
        _lstSessionBalance += amount;
    }

    function _decrementWethSessionBalance(uint256 amount) private {
        require(_wethSessionBalance >= amount, "Insufficient WETH session balance");

        _wethSessionBalance -= amount;
    }

    function _decrementLstSessionBalance(uint256 amount) private {
        require(_lstSessionBalance >= amount, "Insufficient LST session balance");

        _lstSessionBalance -= amount;
    }

    function _loadAaveAccountData(uint256 ethPrice, uint256 lstPrice)
        private
        view
        returns (AaveAccount.Data memory aaveAccount)
    {
        aaveAccount.initialize(AAVE_POOL, address(this), ethPrice, lstPrice);
    }

    // ---------------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------------

    function setTargetHealthFactor(uint256 _targetHealthFactor) external onlyOwner {
        require(_targetHealthFactor >= MIN_TARGET_HEALTH_FACTOR, "Target HF too low");
        targetHealthFactor = _targetHealthFactor;
    }

    function setAllowedUnwindSlippage(uint256 _allowedUnwindSlippage) external onlyOwner {
        require(_allowedUnwindSlippage <= MAX_UNWIND_SLIPPAGE, "Slippage too high");
        allowedUnwindSlippage = _allowedUnwindSlippage;
    }

    receive() external payable {
        // Only accept ETH from the WETH contract. The vault calls WETH.withdraw to unwrap WETH before
        // calling stake on the LST contract.
        require(msg.sender == address(WETH), "Not WETH");
    }
}
