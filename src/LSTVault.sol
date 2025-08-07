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
import {ISonicStaking} from "./interfaces/ISonicStaking.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AaveAccount} from "./libraries/AaveAccount.sol";
import {console} from "forge-std/console.sol";

/**
 * @title LSTVault
 * @notice Vault that lets users create a leveraged wstETH position on Aave via an atomic, flash‑loan‑style callback.
 *         Vault shares are ERC20 and track a proportional claim on net asset value (ETH terms).
 */
contract LSTVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using AaveAccount for AaveAccount.Data;

    uint256 public constant VARIABLE_INTEREST_RATE = 2;
    uint256 public constant MIN_LST_DEPOSIT = 0.01e18; // 0.01
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.01e18; // 0.01
    uint256 public constant MAX_UNWIND_SLIPPAGE = 0.02e18; // 2%

    // ---------------------------------------------------------------------
    // External protocol references (immutable after deployment)
    // ---------------------------------------------------------------------
    IWETH public immutable WETH;
    ISonicStaking public immutable LST;
    IAavePool public immutable aavePool;

    bool public isInitialized = false;
    uint256 public targetHealthFactor = 1.3e18;
    uint256 public allowedUnwindSlippage = 0.007e18; // 0.7%

    // ---------------------------------------------------------------------
    // Flash‑accounting operation state (transient; zeroed every execution)
    // ---------------------------------------------------------------------
    bool private transient locked;
    address private transient allowedCaller;
    uint256 private transient _sessionBalanceWETH;
    uint256 private transient _sessionBalanceLST;

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
        aavePool = IAavePool(_aavePool);

        // Approve Aave once for both tokens (safe since Aave pool is trusted)
        IERC20(_weth).approve(_aavePool, type(uint256).max);
        IERC20(_lst).approve(_aavePool, type(uint256).max);
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyWhenLocked() {
        require(locked, "Not locked");
        require(msg.sender == allowedCaller, "Not allowed");

        _;
    }

    modifier acquireLock() {
        require(!locked, "Op in progress");

        locked = true;
        allowedCaller = msg.sender;

        _;

        locked = false;
        allowedCaller = address(0);
    }

    modifier whenInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    // ---------------------------------------------------------------------
    // Primary entry points: atomic leveraged deposit and withdraw operations
    // ---------------------------------------------------------------------

    /**
     * @param data Arbitrary calldata forwarded to the callback.
     */
    function deposit(address receiver, bytes calldata data) external nonReentrant whenInitialized acquireLock {
        uint256 ethPrice = getEthPrice();

        // -------------------- Pre‑state snapshot -------------------------
        AaveAccount.Data memory aaveAccountBefore = _loadAaveAccountData(ethPrice);

        uint256 navBefore = aaveAccountBefore.netAssetValueInETH();

        // ----------------------- Callback -------------------------------
        (msg.sender).functionCall(data);

        // -------------------- Post checks -------------------------------

        // You must clear your session balance by the end of a deposit operation
        require(_sessionBalanceWETH == 0, "WETH session balance != 0");
        require(_sessionBalanceLST == 0, "LST session balance != 0");

        AaveAccount.Data memory aaveAccountAfter = _loadAaveAccountData(ethPrice);
        uint256 navAfter = aaveAccountAfter.netAssetValueInETH();

        uint256 navIncrease = navAfter - navBefore;

        require(navIncrease >= MIN_DEPOSIT_AMOUNT, "Net change < min");

        // TODO: investigate what is the best margin to use here
        if (aaveAccountBefore.healthFactor < targetHealthFactor) {
            require(aaveAccountAfter.healthFactor >= aaveAccountBefore.healthFactor * 0.999e18 / 1e18, "HF < target");
        } else {
            require(aaveAccountAfter.healthFactor >= targetHealthFactor * 0.999e18 / 1e18, "HF < target");
        }

        // we issue shares such that the invariant of totalAssets / totalSupply is preserved, rounding down
        uint256 shares = totalSupply() * navIncrease / navBefore;

        _mint(receiver, shares);
    }

    /**
     * @param sharesToRedeem Amount of vault shares to burn.
     * @param data          Arbitrary calldata forwarded to the callback.
     */
    function withdraw(uint256 sharesToRedeem, bytes calldata data) external nonReentrant whenInitialized acquireLock {
        require(sharesToRedeem > 0.01e18, "Not enough shares");

        uint256 ethPrice = getEthPrice();

        // -------------------- Pre‑state snapshot -------------------------

        AaveAccount.Data memory aaveAccountBefore = _loadAaveAccountData(ethPrice);
        uint256 navBefore = aaveAccountBefore.netAssetValueInETH();
        uint256 totalSupplyBefore = totalSupply();

        // calculate the portion of debt and collateral that belongs to the amount of shares being redeemed
        uint256 debtToRepay = aaveAccountBefore.totalDebtBase * sharesToRedeem / totalSupplyBefore;
        uint256 collateralToWithdraw = aaveAccountBefore.totalCollateralBase * sharesToRedeem / totalSupplyBefore;
        uint256 navForShares = navBefore * sharesToRedeem / totalSupplyBefore;

        uint256 expectedDebtAfter = aaveAccountBefore.totalDebtBase - debtToRepay;
        uint256 expectedCollateralAfter = aaveAccountBefore.totalCollateralBase - collateralToWithdraw;
        uint256 expectedNavAfter = navBefore - navForShares;

        // Burn shares up‑front for withdrawals
        // The caller must have the shares, this is an additional erc20 transfer, but avoids a second layer
        // of token approval checks
        _burn(msg.sender, sharesToRedeem);

        // ----------------------- Callback -------------------------------
        (msg.sender).functionCall(data);

        // -------------------- Post checks -------------------------------

        // You must clear your session balance by the end of a withdraw operation
        require(_sessionBalanceWETH == 0, "WETH session balance != 0");
        require(_sessionBalanceLST == 0, "LST session balance != 0");

        AaveAccount.Data memory aaveAccountAfter = _loadAaveAccountData(ethPrice);
        uint256 navAfter = aaveAccountAfter.netAssetValueInETH();

        // TODO: investigate what is the best margin to use here
        require(
            aaveAccountAfter.totalDebtBase <= expectedDebtAfter * 1.000001e18 / 1e18
                && aaveAccountAfter.totalDebtBase >= expectedDebtAfter * 0.999999e18 / 1e18,
            "Debt != expected"
        );
        require(
            aaveAccountAfter.totalCollateralBase <= expectedCollateralAfter * 1.000001e18 / 1e18
                && aaveAccountAfter.totalCollateralBase >= expectedCollateralAfter * 0.999999e18 / 1e18,
            "Collateral != expected"
        );
        require(
            navAfter <= expectedNavAfter * 1.000001e18 / 1e18 && navAfter >= expectedNavAfter * 0.999999e18 / 1e18,
            "Nav != expected"
        );
        //TODO: should we do a health factor check here?
    }

    function initialize() external nonReentrant onlyOwner acquireLock {
        require(!isInitialized, "Already initialized");

        uint256 initAmount = 1 ether;

        pullWETH(initAmount);

        stakeWETH(initAmount);

        aaveSupplyLST(_sessionBalanceLST);

        aavePool.setUserEMode(1);
        aavePool.setUserUseReserveAsCollateral(address(LST), true);

        AaveAccount.Data memory aaveAccount = _loadAaveAccountData(getEthPrice());

        require(aaveAccount.totalDebtBase == 0, "Debt != 0");
        require(_sessionBalanceWETH == 0, "WETH session balance != 0");
        require(_sessionBalanceLST == 0, "LST session balance != 0");

        // Since the vault will have no debt and will have earned no interest at this point, the total collateral is
        // the amount of shares to mint
        uint256 sharesToMint = aaveAccount.baseToETH(aaveAccount.totalCollateralBase);

        //TODO: revisit this, ideally this is the zero address
        // we burn the initial shares so that the total supply will never return to 0
        _mint(address(1), sharesToMint);

        isInitialized = true;
    }

    function unwind(uint256 lstAmountToWithdraw, bytes calldata data)
        external
        nonReentrant
        onlyOwner
        whenInitialized
        acquireLock
    {
        require(lstAmountToWithdraw > 0.01e18, "Not enough collateral");

        this.aaveWithdrawLST(lstAmountToWithdraw);

        this.sendLST(msg.sender, lstAmountToWithdraw);

        // The redemption amount is the true value of the collateral, in ETH terms. It is the amount of WETH that
        // we would receive from doing the time based redemption of the LST.
        uint256 redemptionAmount = _toEth(lstAmountToWithdraw);

        allowedCaller = address(0);

        // The callback will sell the LST and return the amount of WETH received.
        bytes memory result = (msg.sender).functionCall(data);
        uint256 wethAmount = abi.decode(result, (uint256));

        allowedCaller = msg.sender;

        require(wethAmount >= redemptionAmount * (1e18 - allowedUnwindSlippage) / 1e18, "Not enough WETH");

        this.pullWETH(wethAmount);

        this.aaveRepayWETH(wethAmount);

        require(_sessionBalanceWETH == 0, "WETH session balance != 0");
        require(_sessionBalanceLST == 0, "LST session balance != 0");
    }

    // ---------------------------------------------------------------------
    // Vault primitives (ONLY callable during an active lock)
    // ---------------------------------------------------------------------

    function stakeWETH(uint256 amount) public onlyWhenLocked returns (uint256 lstAmount) {
        require(amount >= MIN_LST_DEPOSIT, "Not enough WETH");

        _decrementSessionBalanceWETH(amount);

        // the LST only accepts native ETH, so we unwrap WETH prior to calling deposit
        WETH.withdraw(amount);

        lstAmount = LST.deposit{value: amount}();

        _incrementSessionBalanceLST(lstAmount);
    }

    function aaveSupplyLST(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        _decrementSessionBalanceLST(amount);

        aavePool.supply(address(LST), amount, address(this), 0);
    }

    function aaveWithdrawLST(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        aavePool.withdraw(address(LST), amount, address(this));

        _incrementSessionBalanceLST(amount);
    }

    function aaveBorrowWETH(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        aavePool.borrow(address(WETH), amount, VARIABLE_INTEREST_RATE, 0, address(this));

        _incrementSessionBalanceWETH(amount);
    }

    function aaveRepayWETH(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        _decrementSessionBalanceWETH(amount);

        aavePool.repay(address(WETH), amount, VARIABLE_INTEREST_RATE, address(this));
    }

    function sendWETH(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0 && to != address(0), "Bad args");

        IERC20(address(WETH)).safeTransfer(to, amount);

        _decrementSessionBalanceWETH(amount);
    }

    function sendLST(address to, uint256 amount) public onlyWhenLocked {
        require(amount > 0 && to != address(0), "Bad args");

        IERC20(address(LST)).safeTransfer(to, amount);

        _decrementSessionBalanceLST(amount);
    }

    function pullWETH(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        WETH.transferFrom(msg.sender, address(this), amount);

        _incrementSessionBalanceWETH(amount);
    }

    function pullLST(uint256 amount) public onlyWhenLocked {
        require(amount > 0, "0 amt");

        LST.transferFrom(msg.sender, address(this), amount);

        _incrementSessionBalanceLST(amount);
    }

    function getEthPrice() public view returns (uint256) {
        return aavePool.ADDRESSES_PROVIDER().getPriceOracle().getAssetPrice(address(WETH));
    }

    function getVaultAaveAccountData() public view returns (AaveAccount.Data memory) {
        return _loadAaveAccountData(getEthPrice());
    }

    function totalAssets() public view returns (uint256) {
        return getVaultAaveAccountData().netAssetValueInETH();
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _toEth(uint256 lstAmount) private view returns (uint256) {
        return LST.convertToAssets(lstAmount);
    }

    function _incrementSessionBalanceWETH(uint256 amount) private {
        _sessionBalanceWETH += amount;
    }

    function _incrementSessionBalanceLST(uint256 amount) private {
        _sessionBalanceLST += amount;
    }

    function _decrementSessionBalanceWETH(uint256 amount) private {
        require(_sessionBalanceWETH >= amount, "Insufficient WETH session balance");

        _sessionBalanceWETH -= amount;
    }

    function _decrementSessionBalanceLST(uint256 amount) private {
        require(_sessionBalanceLST >= amount, "Insufficient LST session balance");

        _sessionBalanceLST -= amount;
    }

    function _loadAaveAccountData(uint256 ethPrice) private view returns (AaveAccount.Data memory aaveAccount) {
        aaveAccount.initialize(aavePool, address(this), ethPrice);
    }

    // ---------------------------------------------------------------------
    // Receive fallback (accept raw ETH from WETH.withdraw/Lido)
    // ---------------------------------------------------------------------
    receive() external payable {}
}
