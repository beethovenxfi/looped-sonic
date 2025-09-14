// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "../libraries/VaultSnapshot.sol";

/**
 * @notice LoopedSonicVault is an ERC20 vault token that implements a looped LST strategy combining stS with Aave v3
 *   on the Sonic network. The vault uses a flash-accounting execution flow similar to Uni V4 and Balncer V3. This
 *   allows for custom router implementations for managing the deposit and withdrawal of assets, allowing for
 *   flexibility in sourcing the best rate when looping and unwinding. The vault maintains strict safety invariants
 *   during an operation.
 */
interface ILoopedSonicVault {
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    /**
     * @notice Emitted when a user deposits assets and receives vault shares
     * @param caller The address that initiated the deposit
     * @param receiver The address that received the minted shares
     * @param sharesMinted The amount of vault shares minted
     * @param navIncreaseEth The increase in net asset value in ETH terms
     */
    event Deposit(
        address indexed caller,
        address indexed receiver,
        uint256 sharesMinted,
        uint256 navIncreaseEth,
        uint256 totalCollateralEth,
        uint256 totalDebtEth,
        uint256 totalSupply
    );

    /**
     * @notice Emitted when a user withdraws assets by burning vault shares
     * @param caller The address that initiated the withdrawal
     * @param sharesBurned The amount of vault shares burned
     * @param navDecreaseEth The decrease in net asset value in ETH terms
     */
    event Withdraw(
        address indexed caller,
        uint256 sharesBurned,
        uint256 navDecreaseEth,
        uint256 totalCollateralEth,
        uint256 totalDebtEth,
        uint256 totalSupply
    );

    /**
     * @notice Emitted when the vault is initialized with initial liquidity
     * @param caller The address that initiated the initialization
     * @param receiver The address that received the initial shares
     * @param sharesMinted The amount of initial shares minted
     * @param navIncreaseEth The initial net asset value in ETH terms
     */
    event Initialize(
        address indexed caller,
        address indexed receiver,
        uint256 sharesMinted,
        uint256 navIncreaseEth,
        uint256 totalCollateralEth,
        uint256 totalDebtEth,
        uint256 totalSupply
    );

    /**
     * @notice Emitted when collateral is unwound through external liquidation
     * @param caller The address that initiated the unwind
     * @param lstAmountCollateralWithdrawn The amount of LST collateral withdrawn
     * @param wethAmountDebtRepaid The amount of WETH debt repaid
     */
    event Unwind(
        address indexed caller,
        uint256 lstAmountCollateralWithdrawn,
        uint256 wethAmountDebtRepaid,
        uint256 totalCollateralEth,
        uint256 totalDebtEth,
        uint256 totalSupply
    );

    /**
     * @notice Emitted when WETH is staked to receive LST
     * @param caller The address that initiated the staking
     * @param wethAmountDeposited The amount of WETH staked
     * @param lstAmountReceived The amount of LST received
     */
    event StakeWeth(address indexed caller, uint256 wethAmountDeposited, uint256 lstAmountReceived);

    /**
     * @notice Emitted when LST is supplied to Aave as collateral
     * @param caller The address that initiated the supply
     * @param lstAmountSupplied The amount of LST supplied
     */
    event AaveSupplyLst(address indexed caller, uint256 lstAmountSupplied);

    /**
     * @notice Emitted when LST collateral is withdrawn from Aave
     * @param caller The address that initiated the withdrawal
     * @param lstAmountWithdrawn The amount of LST withdrawn
     */
    event AaveWithdrawLst(address indexed caller, uint256 lstAmountWithdrawn);

    /**
     * @notice Emitted when WETH is borrowed from Aave
     * @param caller The address that initiated the borrow
     * @param wethAmountBorrowed The amount of WETH borrowed
     */
    event AaveBorrowWeth(address indexed caller, uint256 wethAmountBorrowed);

    /**
     * @notice Emitted when WETH debt is repaid to Aave
     * @param caller The address that initiated the repayment
     * @param wethAmountRepaid The amount of WETH repaid
     */
    event AaveRepayWeth(address indexed caller, uint256 wethAmountRepaid);

    /**
     * @notice Emitted when WETH is sent from the vault
     * @param caller The address that initiated the transfer
     * @param to The recipient address
     * @param amount The amount of WETH sent
     */
    event SendWeth(address indexed caller, address indexed to, uint256 amount);

    /**
     * @notice Emitted when LST is sent from the vault
     * @param caller The address that initiated the transfer
     * @param to The recipient address
     * @param amount The amount of LST sent
     */
    event SendLst(address indexed caller, address indexed to, uint256 amount);

    /**
     * @notice Emitted when WETH is pulled into the vault
     * @param caller The address that initiated the transfer
     * @param from The sender address
     * @param amount The amount of WETH pulled
     */
    event PullWeth(address indexed caller, address indexed from, uint256 amount);

    /**
     * @notice Emitted when LST is pulled into the vault
     * @param caller The address that initiated the transfer
     * @param from The sender address
     * @param amount The amount of LST pulled
     */
    event PullLst(address indexed caller, address indexed from, uint256 amount);

    /**
     * @notice Emitted when deposit pause status changes
     * @param paused The new pause status for deposits
     */
    event DepositsPausedChanged(bool paused);

    /**
     * @notice Emitted when withdraw pause status changes
     * @param paused The new pause status for withdrawals
     */
    event WithdrawsPausedChanged(bool paused);

    /**
     * @notice Emitted when unwind pause status changes
     * @param paused The new pause status for unwinds
     */
    event UnwindsPausedChanged(bool paused);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error NotLocked();
    error NotAllowed();
    error Locked();
    error WethSessionBalanceNotZero();
    error LstSessionBalanceNotZero();
    error NotInitialized();
    error DepositsPaused();
    error NavIncreaseBelowMin();
    error HealthFactorNotInRange();
    error WithdrawsPaused();
    error NotEnoughShares();
    error InvalidDebtAfterWithdraw();
    error InvalidCollateralAfterWithdraw();
    error InvalidNavAfterWithdraw();
    error AlreadyInitialized();
    error CollateralNotZero();
    error UnwindsPaused();
    error UnwindAmountBelowMin();
    error NotEnoughWeth();
    error ZeroAmount();
    error AmountLessThanMin();
    error InsufficientWethSessionBalance();
    error InsufficientLstSessionBalance();
    error SenderNotWethContract();
    error TargetHealthFactorTooLow();
    error SlippageTooHigh();
    error ZeroShares();
    error SharesExceedTotalSupply();
    error LstRateChanged();
    error TotalSupplyNotZero();
    error AmountGreaterThanWethDebt();

    // ---------------------------------------------------------------------
    // Primary vault operations
    // ---------------------------------------------------------------------

    /**
     * @notice Deposits assets into the vault and mints shares via atomic callback execution
     * @dev Acquires lock, executes callback, enforces invariants (HF ≥ target, no share price decrease)
     * @param receiver The address to receive the minted vault shares
     * @param callbackData Arbitrary calldata forwarded to the callback for deposit logic
     */
    function deposit(address receiver, bytes calldata callbackData) external returns (uint256 shares);

    /**
     * @notice Withdraws assets from the vault by burning shares via atomic callback execution
     * @dev Burns shares upfront, executes callback, enforces proportional asset withdrawal
     * @param sharesToRedeem The amount of vault shares to burn for withdrawal
     * @param callbackData Arbitrary calldata forwarded to the callback for withdrawal logic
     */
    function withdraw(uint256 sharesToRedeem, bytes calldata callbackData) external;

    /**
     * @notice Initializes the vault with initial liquidity (owner only)
     * @dev Stakes initial WETH to LST, supplies to Aave, sets up e-mode, mints initial shares
     */
    function initialize() external;

    /**
     * @notice Unwinds vault position by withdrawing LST collateral and selling externally (operator only)
     * @dev Withdraws LST from Aave, sends to caller, executes external sale, repays WETH debt
     * @param lstAmountToWithdraw The amount of LST collateral to withdraw and sell
     * @param data The calldata for the external liquidation contract
     */
    function unwind(uint256 lstAmountToWithdraw, bytes calldata data) external;

    // ---------------------------------------------------------------------
    // Vault primitives (only callable during active lock)
    // ---------------------------------------------------------------------

    /**
     * @notice Stakes WETH to receive LST via the staking contract (locked operation only)
     * @dev Unwraps WETH to ETH, calls LST deposit, updates session balance
     * @param amount The amount of WETH to stake
     * @return lstAmount The amount of LST received from staking
     */
    function stakeWeth(uint256 amount) external returns (uint256 lstAmount);

    /**
     * @notice Supplies LST as collateral to Aave (locked operation only)
     * @dev Calls Aave pool supply function, reduces LST session balance
     * @param amount The amount of LST to supply as collateral
     */
    function aaveSupplyLst(uint256 amount) external;

    /**
     * @notice Withdraws LST collateral from Aave (locked operation only)
     * @dev Calls Aave pool withdraw function, increases LST session balance
     * @param amount The amount of LST to withdraw from Aave
     */
    function aaveWithdrawLst(uint256 amount) external;

    /**
     * @notice Borrows WETH from Aave using LST collateral (locked operation only)
     * @dev Calls Aave pool borrow function with variable rate, increases WETH session balance
     * @param amount The amount of WETH to borrow
     */
    function aaveBorrowWeth(uint256 amount) external;

    /**
     * @notice Repays WETH debt to Aave (locked operation only)
     * @dev Calls Aave pool repay function, reduces WETH session balance
     * @param amount The amount of WETH debt to repay
     */
    function aaveRepayWeth(uint256 amount) external;

    /**
     * @notice Sends WETH from vault to specified address (locked operation only)
     * @dev Transfers WETH tokens, reduces WETH session balance
     * @param to The recipient address for WETH transfer
     * @param amount The amount of WETH to send
     */
    function sendWeth(address to, uint256 amount) external;

    /**
     * @notice Sends LST from vault to specified address (locked operation only)
     * @dev Transfers LST tokens, reduces LST session balance
     * @param to The recipient address for LST transfer
     * @param amount The amount of LST to send
     */
    function sendLst(address to, uint256 amount) external;

    /**
     * @notice Pulls WETH from caller into vault (locked operation only)
     * @dev Transfers WETH from caller to vault, increases WETH session balance
     * @param amount The amount of WETH to pull from caller
     */
    function pullWeth(uint256 amount) external;

    /**
     * @notice Pulls LST from caller into vault (locked operation only)
     * @dev Transfers LST from caller to vault, increases LST session balance
     * @param amount The amount of LST to pull from caller
     */
    function pullLst(uint256 amount) external;

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /**
     * @notice Gets the vault's current snapshot including collateral, debt, and health factor
     * @return snapshot Structured data containing vault's position details
     */
    function getVaultSnapshot() external view returns (VaultSnapshot.Data memory snapshot);

    /**
     * @notice Gets the total asset value of the vault in ETH terms (net asset value)
     * @dev Can only be called when vault is not locked
     * @return The total assets managed by the vault in ETH terms
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Converts vault shares to underlying asset amount
     * @dev Can only be called when vault is not locked
     * @param shares The amount of vault shares to convert
     * @return The equivalent amount of underlying assets in ETH terms
     */
    function convertToAssets(uint256 shares) external view returns (uint256);

    /**
     * @notice Converts underlying asset amount to vault shares
     * @dev Can only be called when vault is not locked
     * @param assets The amount of underlying assets in ETH terms
     * @return The equivalent amount of vault shares
     */
    function convertToShares(uint256 assets) external view returns (uint256);

    /**
     * @notice Gets the current exchange rate (assets per share)
     * @dev Can only be called when vault is not locked
     * @return The amount of assets that 1 ether of shares represents
     */
    function getRate() external view returns (uint256);

    /**
     * @notice Gets the proportional collateral and debt for a given amount of shares
     * @dev Can only be called when vault is not locked
     * @param shares The amount of shares to calculate proportional amounts for
     * @return collateralInLst The proportional LST collateral amount
     * @return debtInEth The proportional WETH debt amount in ETH terms
     */
    function getCollateralAndDebtForShares(uint256 shares)
        external
        view
        returns (uint256 collateralInLst, uint256 debtInEth);

    /**
     * @notice Gets the current session balances for WETH and LST during locked operations
     * @dev Returns the transient session balances tracked during atomic operations
     * @return wethSessionBalance The current WETH session balance
     * @return lstSessionBalance The current LST session balance
     */
    function getSessionBalances() external view returns (uint256 wethSessionBalance, uint256 lstSessionBalance);

    /**
     * @notice Gets the amount of LST collateral deposited in Aave
     * @dev Returns the balance of LST aTokens held by the vault
     * @return The amount of LST collateral in Aave
     */
    function getAaveLstCollateralAmount() external view returns (uint256);

    /**
     * @notice Gets the amount of WETH debt owed to Aave
     * @dev Returns the balance of WETH variable debt tokens held by the vault
     * @return The amount of WETH debt in Aave
     */
    function getAaveWethDebtAmount() external view returns (uint256);

    /**
     * @notice Gets the current health factor of the vault's Aave position
     * @dev Returns the health factor calculated from collateral and debt amounts
     * @return The current health factor (18 decimals)
     */
    function getHealthFactor() external view returns (uint256);

    /**
     * @notice Gets the optimal borrow amount for looping based on target health factor
     * @dev Calculates how much WETH can be borrowed while maintaining target health factor
     * @return The optimal borrow amount in ETH terms
     */
    function getBorrowAmountForLoopInEth() external view returns (uint256);

    // ---------------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------------

    /**
     * @notice Sets the target health factor for vault operations (owner only)
     * @dev Must be greater than or equal to minimum target health factor (1.1)
     * @param _targetHealthFactor The new target health factor (18 decimals)
     */
    function setTargetHealthFactor(uint256 _targetHealthFactor) external;

    /**
     * @notice Sets the allowed slippage for unwind operations (owner only)
     * @dev Must be less than or equal to maximum unwind slippage (2%)
     * @param _allowedUnwindSlippagePercent The new allowed slippage (18 decimals)
     */
    function setAllowedUnwindSlippagePercent(uint256 _allowedUnwindSlippagePercent) external;

    /**
     * @notice Sets the Aave Capo rate provider address (owner only)
     * @dev Updates the rate provider used for pricing LST collateral
     * @param _aaveCapoRateProvider The new rate provider contract address
     */
    function setAaveCapoRateProvider(address _aaveCapoRateProvider) external;

    /**
     * @notice Pauses all vault operations (operator role only)
     * @dev Sets all pause flags to true: deposits, withdrawals, unwinds
     */
    function pause() external;

    /**
     * @notice Sets the pause status for deposit operations (owner only)
     * @param _paused True to pause deposits, false to unpause
     */
    function setDepositsPaused(bool _paused) external;

    /**
     * @notice Sets the pause status for withdrawal operations (owner only)
     * @param _paused True to pause withdrawals, false to unpause
     */
    function setWithdrawsPaused(bool _paused) external;

    /**
     * @notice Sets the pause status for unwind operations (owner only)
     * @param _paused True to pause unwinds, false to unpause
     */
    function setUnwindsPaused(bool _paused) external;
}
