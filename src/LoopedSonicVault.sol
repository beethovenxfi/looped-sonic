// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISonicStaking} from "./interfaces/ISonicStaking.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {VaultSnapshot} from "./libraries/VaultSnapshot.sol";
import {VaultSnapshotComparison} from "./libraries/VaultSnapshotComparison.sol";
import {ILoopedSonicVault} from "./interfaces/ILoopedSonicVault.sol";
import {IAaveCapoRateProvider} from "./interfaces/IAaveCapoRateProvider.sol";
import {IPool} from "aave-v3-origin/interfaces/IPool.sol";
import {IPoolDataProvider} from "aave-v3-origin/interfaces/IPoolDataProvider.sol";
import {DataTypes} from "aave-v3-origin/protocol/libraries/types/DataTypes.sol";
import {IScaledBalanceToken} from "aave-v3-origin/interfaces/IScaledBalanceToken.sol";

contract LoopedSonicVault is ERC20, AccessControl, ILoopedSonicVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UNWIND_ROLE = keccak256("UNWIND_ROLE");

    uint256 public constant AAVE_VARIABLE_INTEREST_RATE = 2;
    uint256 public constant MIN_LST_DEPOSIT = 0.01e18; // 0.01
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.01e18; // 0.01
    uint256 public constant MIN_UNWIND_AMOUNT = 0.01e18; // 0.01
    uint256 public constant MAX_UNWIND_SLIPPAGE_PERCENT = 0.02e18; // 2%
    uint256 public constant MIN_NAV_INCREASE_ETH = 0.01e18; // 0.01 ETH
    uint256 public constant MIN_TARGET_HEALTH_FACTOR = 1.1e18; // 1.1
    uint256 public constant MIN_SHARES_TO_REDEEM = 0.01e18; // 0.01
    uint256 public constant INIT_AMOUNT = 1e18; // 1 ETH
    uint256 public constant MAX_PROTOCOL_FEE_PERCENT = 0.5e18; // 50%

    // ---------------------------------------------------------------------
    // External protocol references (immutable after deployment)
    // ---------------------------------------------------------------------
    IWETH public immutable WETH;
    ISonicStaking public immutable LST;
    IPool public immutable AAVE_POOL;
    IERC20 public immutable LST_A_TOKEN;
    IERC20 public immutable WETH_VARIABLE_DEBT_TOKEN;
    uint8 public immutable AAVE_E_MODE_CATEGORY_ID;

    bool public isInitialized = false;

    uint256 public targetHealthFactor;
    uint256 public allowedUnwindSlippagePercent;

    uint256 public protocolFeePercent;
    address public treasuryAddress;
    // We take the approach of only charging a protocol fee on rate growth once. This avoids double charging as the
    // rate trends down as debt accrues inbetween stS harvests. It is understood that this approach is not perfect.
    // In instances where the rate goes down and tvl increases signficantly, fees on the grown of the new tvl will not
    // be captured.
    uint256 public athRate;

    bool public depositsPaused = false;
    bool public withdrawsPaused = false;
    bool public unwindsPaused = false;

    // The stS Aave market uses a correlated asset price oracle (CAPO). To avoid the precision loss of using the base
    // currency (8 decimals), we read the exact rate from the CAP feed and use this rate to price the LST collateral
    // in ETH. This ensures that if the rate growth of stS exceeds the max ratio, the vault will not overprice it's LST
    // collateral. While unlikely, in the event that the Aave market changes the stS oracle, we allow for the rate
    // provider to be updated by the admin.
    IAaveCapoRateProvider public aaveCapoRateProvider;

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
    constructor(
        address _weth,
        address _lst,
        address _aavePool,
        uint8 _eModeCategoryId,
        address _aaveCapoRateProvider,
        uint256 _targetHealthFactor,
        uint256 _allowedUnwindSlippagePercent,
        address _admin,
        address _treasuryAddress
    ) ERC20("Beets Aave Looped Sonic", "lS") {
        require(
            _weth != address(0) && _lst != address(0) && _aavePool != address(0) && _admin != address(0)
                && _aaveCapoRateProvider != address(0),
            ZeroAddress()
        );
        require(_targetHealthFactor >= MIN_TARGET_HEALTH_FACTOR, TargetHealthFactorTooLow());

        targetHealthFactor = _targetHealthFactor;

        _setAllowedUnwindSlippagePercent(_allowedUnwindSlippagePercent);

        WETH = IWETH(_weth);
        LST = ISonicStaking(_lst);
        AAVE_POOL = IPool(_aavePool);
        LST_A_TOKEN = IERC20(AAVE_POOL.getReserveAToken(address(LST)));
        (,, address wethVariableDebtToken) =
            IPoolDataProvider(AAVE_POOL.ADDRESSES_PROVIDER().getPoolDataProvider()).getReserveTokensAddresses(_weth);
        WETH_VARIABLE_DEBT_TOKEN = IERC20(wethVariableDebtToken);

        AAVE_E_MODE_CATEGORY_ID = _eModeCategoryId;

        aaveCapoRateProvider = IAaveCapoRateProvider(_aaveCapoRateProvider);

        // Approve Aave once for both tokens
        IERC20(_weth).approve(_aavePool, type(uint256).max);
        IERC20(_lst).approve(_aavePool, type(uint256).max);

        // Grant admin role to admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        treasuryAddress = _treasuryAddress;
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier whenLocked() {
        require(locked, NotLocked());
        require(msg.sender == allowedCaller, NotAllowed());

        _;
    }

    modifier whenNotLocked() {
        require(!locked, Locked());
        _;
    }

    modifier acquireLock() {
        require(!locked, Locked());

        locked = true;
        allowedCaller = msg.sender;
        uint256 rateBefore = aaveCapoRateProvider.getRate();

        _;

        // You must clear your session balance by the end of any operation that acquires a lock
        require(_wethSessionBalance == 0, WethSessionBalanceNotZero());
        require(_lstSessionBalance == 0, LstSessionBalanceNotZero());

        // If the LST rate changes during the lock, the vault would incorrectly attribute the NAV increase/decrease
        // to this operation. We strictly disallow it.
        require(rateBefore == aaveCapoRateProvider.getRate(), LstRateChanged());

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
     * @inheritdoc ILoopedSonicVault
     */
    function deposit(address receiver, bytes calldata callbackData)
        external
        whenInitialized
        acquireLock
        returns (uint256 shares)
    {
        require(!depositsPaused, DepositsPaused());
        require(receiver != address(0), ZeroAddress());

        // Protocol fees are paid immediately before a deposit. This ensures that any pending protocol fee
        // is paid by the current share holders before new shares are issued.
        _payProtocolFees();

        VaultSnapshotComparison.Data memory data;

        // Store the vault state before the callback performs the deposit
        data.stateBefore = getVaultSnapshot();

        // Execute the callback, giving control back to the caller to perform the deposit
        (msg.sender).functionCall(callbackData);

        // At this point the actualSupply is in an incorrect state, as the shares for the deposit have not yet been
        // minted. None of the operations below access the actualSupply for this snapshot.
        data.stateAfter = getVaultSnapshot();

        uint256 navIncreaseEth = data.navIncreaseEth();

        require(navIncreaseEth >= MIN_NAV_INCREASE_ETH, NavIncreaseBelowMin());

        require(data.checkHealthFactorAfterDeposit(targetHealthFactor), HealthFactorNotInRange());

        // Issue shares such that the invariant of totalAssets / totalSupply is preserved, rounding down

        // We MUST use totalSupply here, the deposit callback has increased the NAV, but new shares have not yet been
        // minted. The rate is inflated until the shares are minted below.
        shares = totalSupply() * navIncreaseEth / data.stateBefore.netAssetValueInEth();

        _mint(receiver, shares);

        emit Deposit(
            msg.sender,
            receiver,
            shares,
            navIncreaseEth,
            data.stateAfter.lstCollateralAmountInEth,
            data.stateAfter.wethDebtAmount,
            totalSupply()
        );
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function withdraw(uint256 sharesToRedeem, bytes calldata callbackData) external whenInitialized acquireLock {
        require(!withdrawsPaused, WithdrawsPaused());
        require(sharesToRedeem >= MIN_SHARES_TO_REDEEM, NotEnoughShares());

        // Protocol fees are paid immediately before a witdhraw. This ensures that any pending protocol fee
        // is paid by the current share holders before shares are burned.
        _payProtocolFees();

        VaultSnapshotComparison.Data memory data;

        data.stateBefore = getVaultSnapshot();

        // Burn shares up‑front for withdrawals . The caller must have the shares (ie: the router), this is an
        // additional erc20 transfer, but avoids a second layer of permissions
        _burn(msg.sender, sharesToRedeem);

        (msg.sender).functionCall(callbackData);

        data.stateAfter = getVaultSnapshot();

        require(data.checkDebtAfterWithdraw(sharesToRedeem), InvalidDebtAfterWithdraw());
        require(data.checkCollateralAfterWithdraw(sharesToRedeem), InvalidCollateralAfterWithdraw());

        emit Withdraw(
            msg.sender,
            sharesToRedeem,
            data.navDecreaseEth(),
            data.stateAfter.lstCollateralAmountInEth,
            data.stateAfter.wethDebtAmount,
            data.stateAfter.actualSupply
        );
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function initialize() external acquireLock {
        require(!isInitialized, AlreadyInitialized());

        VaultSnapshot.Data memory snapshotBefore = getVaultSnapshot();

        require(snapshotBefore.actualSupply == 0, TotalSupplyNotZero());
        require(snapshotBefore.lstCollateralAmount == 0, CollateralNotZero());

        pullWeth(INIT_AMOUNT);

        stakeWeth(INIT_AMOUNT);

        aaveSupplyLst(_lstSessionBalance);

        AAVE_POOL.setUserEMode(AAVE_E_MODE_CATEGORY_ID);
        AAVE_POOL.setUserUseReserveAsCollateral(address(LST), true);

        VaultSnapshot.Data memory snapshotAfter = getVaultSnapshot();

        // Since the vault's nav was 0 before initialization, the amount of shares to mint is the nav, valued in ETH
        uint256 sharesToMint = snapshotAfter.netAssetValueInEth();

        // We burn the initial shares so that the total supply will never return to 0
        // We use address(1) since openzeppelin's ERC20 does not allow minting to the zero address
        _mint(address(1), sharesToMint);

        isInitialized = true;

        // We start the athRate at 1e18
        athRate = 1e18;

        emit Initialize(
            msg.sender,
            address(1),
            sharesToMint,
            sharesToMint,
            snapshotAfter.lstCollateralAmountInEth,
            snapshotAfter.wethDebtAmount,
            sharesToMint
        );
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function unwind(uint256 lstAmountToWithdraw, bytes calldata data)
        external
        onlyRole(UNWIND_ROLE)
        whenInitialized
        acquireLock
    {
        require(!unwindsPaused, UnwindsPaused());
        require(lstAmountToWithdraw > MIN_UNWIND_AMOUNT, UnwindAmountBelowMin());

        // Aave will revert any withdraw that would cause the health factor to drop below 1.0
        aaveWithdrawLst(lstAmountToWithdraw);

        sendLst(msg.sender, lstAmountToWithdraw);

        // The redemption amount is the true value of the collateral, in ETH terms. It is the amount of WETH that
        // we would receive from doing the time delayed redemption of the LST.
        uint256 redemptionAmount = LST.convertToAssets(lstAmountToWithdraw);

        // Disallow msg.sender from calling into the vault during the scope of the callback
        // This ensures the operator cannot impact vault state during the callback.
        allowedCaller = address(0);

        // The callback will sell the LST and return the amount of WETH received.
        bytes memory result = (msg.sender).functionCall(data);
        uint256 wethAmount = abi.decode(result, (uint256));

        require(wethAmount >= redemptionAmount * (1e18 - allowedUnwindSlippagePercent) / 1e18, NotEnoughWeth());

        // Reassign the allowedCaller so we can call the vault primitives below
        allowedCaller = msg.sender;

        pullWeth(wethAmount);

        aaveRepayWeth(wethAmount);

        VaultSnapshot.Data memory snapshot = getVaultSnapshot();

        emit Unwind(
            msg.sender,
            lstAmountToWithdraw,
            wethAmount,
            snapshot.lstCollateralAmountInEth,
            snapshot.wethDebtAmount,
            snapshot.actualSupply
        );
    }

    // ---------------------------------------------------------------------
    // Vault primitives (ONLY callable during an active lock)
    // ---------------------------------------------------------------------

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function stakeWeth(uint256 amount) public whenLocked returns (uint256 lstAmount) {
        require(amount >= MIN_LST_DEPOSIT, AmountLessThanMin());

        _decrementWethSessionBalance(amount);

        // the LST only accepts native ETH, so we unwrap prior to calling deposit
        WETH.withdraw(amount);

        lstAmount = LST.deposit{value: amount}();

        _incrementLstSessionBalance(lstAmount);

        emit StakeWeth(allowedCaller, amount, lstAmount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function aaveSupplyLst(uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());

        _decrementLstSessionBalance(amount);

        AAVE_POOL.supply(address(LST), amount, address(this), 0);

        emit AaveSupplyLst(allowedCaller, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function aaveWithdrawLst(uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());

        AAVE_POOL.withdraw(address(LST), amount, address(this));

        _incrementLstSessionBalance(amount);

        emit AaveWithdrawLst(allowedCaller, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function aaveBorrowWeth(uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());

        AAVE_POOL.borrow(address(WETH), amount, AAVE_VARIABLE_INTEREST_RATE, 0, address(this));

        _incrementWethSessionBalance(amount);

        emit AaveBorrowWeth(allowedCaller, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function aaveRepayWeth(uint256 amount) public whenLocked {
        uint256 wethDebtAmount = getAaveWethDebtAmount();

        require(amount > 0, ZeroAmount());
        // If we overpay, Aave will send WETH back to the vault, which would not be accounted for.
        require(amount <= getAaveWethDebtAmount(), AmountGreaterThanWethDebt());

        _decrementWethSessionBalance(amount);

        AAVE_POOL.repay(
            address(WETH),
            // In the instance that we're paying back the entire debt, we use type(uint256).max to avoid leaving dust.
            amount == wethDebtAmount ? type(uint256).max : amount,
            AAVE_VARIABLE_INTEREST_RATE,
            address(this)
        );

        emit AaveRepayWeth(allowedCaller, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function sendWeth(address to, uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());
        require(to != address(0), ZeroAddress());

        _decrementWethSessionBalance(amount);

        IERC20(address(WETH)).safeTransfer(to, amount);

        emit SendWeth(allowedCaller, to, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function sendLst(address to, uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());
        require(to != address(0), ZeroAddress());

        _decrementLstSessionBalance(amount);

        IERC20(address(LST)).safeTransfer(to, amount);

        emit SendLst(allowedCaller, to, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function pullWeth(uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());

        IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementWethSessionBalance(amount);

        emit PullWeth(allowedCaller, msg.sender, amount);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function pullLst(uint256 amount) public whenLocked {
        require(amount > 0, ZeroAmount());

        IERC20(address(LST)).safeTransferFrom(msg.sender, address(this), amount);

        _incrementLstSessionBalance(amount);

        emit PullLst(allowedCaller, msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getVaultSnapshot() public view returns (VaultSnapshot.Data memory data) {
        data.wethDebtAmount = getAaveWethDebtAmount();
        data.lstCollateralAmount = getAaveLstCollateralAmount();
        data.lstCollateralAmountInEth = aaveCapoRateProvider.convertToAssets(data.lstCollateralAmount);

        DataTypes.CollateralConfig memory collateralConfig =
            AAVE_POOL.getEModeCategoryCollateralConfig(AAVE_E_MODE_CATEGORY_ID);
        data.ltv = collateralConfig.ltv;
        data.liquidationThreshold = collateralConfig.liquidationThreshold;

        data.actualSupply = _actualSupply();

        data.lstATokenBalance = IScaledBalanceToken(address(LST_A_TOKEN)).scaledBalanceOf(address(this));
        data.wethDebtTokenBalance =
            IScaledBalanceToken(address(WETH_VARIABLE_DEBT_TOKEN)).scaledBalanceOf(address(this));

        data.wethVariableBorrowIndex = AAVE_POOL.getReserveData(address(WETH)).variableBorrowIndex;
        data.lstLiquidityIndex = AAVE_POOL.getReserveData(address(LST)).liquidityIndex;
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function totalAssets() public view whenNotLocked returns (uint256) {
        return getVaultSnapshot().netAssetValueInEth();
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function convertToAssets(uint256 shares) external view whenNotLocked returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 actualShares = _actualSupply();

        if (assetsTotal == 0 || actualShares == 0) {
            return shares;
        }

        return (shares * assetsTotal) / actualShares;
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function convertToShares(uint256 assets) external view whenNotLocked returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 actualShares = _actualSupply();

        if (assetsTotal == 0 || actualShares == 0) {
            return assets;
        }

        return (assets * actualShares) / assetsTotal;
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getRate() external view whenNotLocked returns (uint256) {
        // The rate is the amount of ETH that 1 share is worth
        return _getRate(_actualSupply());
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getCollateralAndDebtForShares(uint256 shares)
        external
        view
        whenNotLocked
        returns (uint256 collateralInLst, uint256 debtInEth)
    {
        VaultSnapshot.Data memory data = getVaultSnapshot();

        require(shares > 0, ZeroShares());
        require(shares <= data.actualSupply, SharesExceedTotalSupply());

        collateralInLst = data.proportionalCollateralInLst(shares);
        debtInEth = data.proportionalDebtInEth(shares);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getSessionBalances() external view returns (uint256 wethSessionBalance, uint256 lstSessionBalance) {
        wethSessionBalance = _wethSessionBalance;
        lstSessionBalance = _lstSessionBalance;
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getAaveLstCollateralAmount() public view returns (uint256) {
        return LST_A_TOKEN.balanceOf(address(this));
    }

    function getAaveLstCollateralAmountInEth() public view returns (uint256) {
        return aaveCapoRateProvider.convertToAssets(getAaveLstCollateralAmount());
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getAaveWethDebtAmount() public view returns (uint256) {
        return WETH_VARIABLE_DEBT_TOKEN.balanceOf(address(this));
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getHealthFactor() external view returns (uint256) {
        return getVaultSnapshot().healthFactor();
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getBorrowAmountForLoopInEth() external view returns (uint256) {
        return getVaultSnapshot().borrowAmountForLoopInEth(targetHealthFactor);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function actualSupply() external view whenNotLocked returns (uint256) {
        return _actualSupply();
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function getPendingProtocolFeeSharesToBeMinted() external view whenNotLocked returns (uint256) {
        return _pendingProtocolFeeSharesToBeMinted();
    }

    // ---------------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------------

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setTargetHealthFactor(uint256 _targetHealthFactor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_targetHealthFactor >= MIN_TARGET_HEALTH_FACTOR, TargetHealthFactorTooLow());
        targetHealthFactor = _targetHealthFactor;

        emit TargetHealthFactorChanged(_targetHealthFactor);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setAaveCapoRateProvider(address _aaveCapoRateProvider) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_aaveCapoRateProvider != address(0), ZeroAddress());

        aaveCapoRateProvider = IAaveCapoRateProvider(_aaveCapoRateProvider);

        emit AaveCapoRateProviderChanged(_aaveCapoRateProvider);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _setDepositsPaused(true);
        _setWithdrawsPaused(true);
        _setUnwindsPaused(true);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setDepositsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDepositsPaused(_paused);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setWithdrawsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setWithdrawsPaused(_paused);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setUnwindsPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUnwindsPaused(_paused);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setAllowedUnwindSlippagePercent(uint256 _allowedUnwindSlippagePercent)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setAllowedUnwindSlippagePercent(_allowedUnwindSlippagePercent);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Prior to setting the new protocol fee percent, pay any pending protocol fees
        _payProtocolFees();

        _setProtocolFeePercent(_protocolFeePercent);
    }

    /**
     * @inheritdoc ILoopedSonicVault
     */
    function setTreasuryAddress(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryAddress != address(0), ZeroAddress());

        treasuryAddress = _treasuryAddress;

        emit TreasuryAddressChanged(_treasuryAddress);
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

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
        require(_wethSessionBalance >= amount, InsufficientWethSessionBalance());

        _wethSessionBalance -= amount;
    }

    function _decrementLstSessionBalance(uint256 amount) private {
        require(_lstSessionBalance >= amount, InsufficientLstSessionBalance());

        _lstSessionBalance -= amount;
    }

    function _pendingProtocolFeeSharesToBeMinted() internal view returns (uint256) {
        if (protocolFeePercent == 0) {
            return 0;
        }

        uint256 currentTotalSupply = totalSupply();
        uint256 rate = _getRate(currentTotalSupply);

        if (rate > athRate && protocolFeePercent > 0) {
            uint256 rateGrowth = rate - athRate;
            uint256 protocolOwnershipPercentage = (rateGrowth * protocolFeePercent) / rate;

            return currentTotalSupply * protocolOwnershipPercentage / (1e18 - protocolOwnershipPercentage);
        }

        return 0;
    }

    function _payProtocolFees() private {
        uint256 sharesToMint = _pendingProtocolFeeSharesToBeMinted();

        if (sharesToMint > 0) {
            _mint(treasuryAddress, sharesToMint);

            // update the athRate to the current rate
            athRate = _getRate(totalSupply());
        }
    }

    function _getRate(uint256 totalSupply) internal view returns (uint256) {
        uint256 nav = getAaveLstCollateralAmountInEth() - getAaveWethDebtAmount();

        if (nav == 0 || totalSupply == 0) {
            return 1e18;
        }

        return nav * 1e18 / totalSupply;
    }

    function _actualSupply() internal view returns (uint256) {
        return totalSupply() + _pendingProtocolFeeSharesToBeMinted();
    }

    function _stripExcessPrecision(uint256 value) internal pure returns (uint256) {
        return value / 1e14 * 1e14;
    }

    function _setAllowedUnwindSlippagePercent(uint256 _allowedUnwindSlippagePercent) internal {
        require(_allowedUnwindSlippagePercent <= MAX_UNWIND_SLIPPAGE_PERCENT, AllowedUnwindSlippageTooHigh());
        require(
            _allowedUnwindSlippagePercent == _stripExcessPrecision(_allowedUnwindSlippagePercent),
            AllowedUnwindSlippageNotInBps()
        );

        allowedUnwindSlippagePercent = _allowedUnwindSlippagePercent;

        emit AllowedUnwindSlippagePercentChanged(_allowedUnwindSlippagePercent);
    }

    function _setProtocolFeePercent(uint256 _protocolFeePercent) internal {
        require(_protocolFeePercent <= MAX_PROTOCOL_FEE_PERCENT, ProtocolFeePercentTooHigh());
        require(_protocolFeePercent == _stripExcessPrecision(_protocolFeePercent), ProtocolFeePercentNotInBps());

        protocolFeePercent = _protocolFeePercent;

        emit ProtocolFeePercentChanged(_protocolFeePercent);
    }

    receive() external payable {
        // Only accept ETH from the WETH contract. The vault calls WETH.withdraw to unwrap WETH before
        // calling stake on the LST contract.
        require(msg.sender == address(WETH), SenderNotWethContract());
    }
}
