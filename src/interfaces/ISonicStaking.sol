// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ISonicStaking
/// @notice Interface for the Sonic Staking contract that issues stS tokens
interface ISonicStaking is IERC20 {
    struct WithdrawRequest {
        uint256 validatorId;
        uint256 amountShares;
        uint256 withdrawId;
        uint256 timeCreated;
        bool isCompleted;
    }

    /// @notice Deposit native S tokens and receive stS shares
    /// @return sharesAmount Amount of stS tokens minted
    function deposit() external payable returns (uint256 sharesAmount);

    /// @notice Undelegate shares from a specific validator (initiates 14-day unbonding)
    /// @param validatorId The validator to undelegate from
    /// @param amountShares Amount of stS shares to undelegate
    /// @return withdrawId The ID of the withdrawal request
    function undelegate(uint256 validatorId, uint256 amountShares) external returns (uint256 withdrawId);

    /// @notice Withdraw previously undelegated assets after unbonding period
    /// @param withdrawId The withdrawal request ID
    /// @param emergency Whether this is an emergency withdrawal
    /// @return amountWithdrawn Amount of S tokens withdrawn
    function withdraw(uint256 withdrawId, bool emergency) external returns (uint256 amountWithdrawn);

    /// @notice Convert asset amount to shares amount
    /// @param assetAmount Amount of S tokens
    /// @return Amount of stS shares
    function convertToShares(uint256 assetAmount) external view returns (uint256);

    /// @notice Convert shares amount to asset amount
    /// @param sharesAmount Amount of stS shares
    /// @return Amount of S tokens
    function convertToAssets(uint256 sharesAmount) external view returns (uint256);

    /// @notice Get the current exchange rate of stS to S
    /// @return rate The current rate (assets per share)
    function getRate() external view returns (uint256 rate);

    /// @notice Get total assets managed by the protocol
    /// @return Total amount of S tokens
    function totalAssets() external view returns (uint256);

    /// @notice Get user's withdrawal requests
    /// @param user User address
    /// @param skip Number of requests to skip
    /// @param maxSize Maximum number of requests to return
    /// @param reverseOrder Whether to return in reverse order
    /// @return Array of withdrawal requests
    function getUserWithdraws(
        address user,
        uint256 skip,
        uint256 maxSize,
        bool reverseOrder
    ) external view returns (WithdrawRequest[] memory);
}