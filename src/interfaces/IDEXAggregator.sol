// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IDEXAggregator
/// @notice Interface for DEX aggregator (1inch, ParaSwap, etc.)
interface IDEXAggregator {
    /// @notice Swap tokens using pre-calculated route data
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
    /// @param amountIn Amount of input tokens
    /// @param minAmountOut Minimum amount of output tokens expected
    /// @param data Pre-calculated swap route data
    /// @return amountOut Actual amount of output tokens received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata data
    ) external returns (uint256 amountOut);

    /// @notice Get expected output amount for a swap (view function)
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
    /// @param amountIn Amount of input tokens
    /// @return amountOut Expected amount of output tokens
    function querySwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}