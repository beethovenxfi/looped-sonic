// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";

/// @title IAavePool
/// @notice Simplified interface for Aave v3 Pool contract
interface IAavePool {
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

    /// @notice Supply assets to the pool
    /// @param asset The address of the asset to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address that will receive aTokens
    /// @param referralCode Code used to register the integrator originating the operation
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /// @notice Borrow assets from the pool
    /// @param asset The address of the asset to borrow
    /// @param amount The amount to borrow
    /// @param interestRateMode The interest rate mode (1 for stable, 2 for variable)
    /// @param referralCode Code used to register the integrator originating the operation
    /// @param onBehalfOf The address receiving the borrowed assets
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    /// @notice Repay borrowed assets
    /// @param asset The address of the asset to repay
    /// @param amount The amount to repay (use type(uint256).max for full repayment)
    /// @param rateMode The interest rate mode
    /// @param onBehalfOf The address for which the repayment is done
    /// @return The final amount repaid
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);

    /// @notice Withdraw supplied assets
    /// @param asset The address of the asset to withdraw
    /// @param amount The amount to withdraw (use type(uint256).max for full withdrawal)
    /// @param to The address that will receive the assets
    /// @return The final amount withdrawn
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /// @notice Get user account data
    /// @param user The address of the user
    /// @return totalCollateralBase Total collateral in base currency
    /// @return totalDebtBase Total debt in base currency
    /// @return availableBorrowsBase Available borrowing capacity in base currency
    /// @return currentLiquidationThreshold Current liquidation threshold
    /// @return ltv Loan to value ratio
    /// @return healthFactor Current health factor
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Allows a user to use the protocol in eMode
     * @param categoryId The id of the category
     */
    function setUserEMode(uint8 categoryId) external;

    /**
     * @notice Allows suppliers to enable/disable a specific supplied asset as collateral
     * @param asset The address of the underlying asset supplied
     * @param useAsCollateral True if the user wants to use the supply as collateral, false otherwise
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}
