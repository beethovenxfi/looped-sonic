// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMagpieRouterV3_1 {
    event UpdateInternalCaller(address indexed sender, address caller, bool value);

    /// @dev Allows the owner to update the whitelisted internal callers.
    /// @param caller Caller address.
    /// @param value Disable or enable the related caller.
    function updateInternalCaller(address caller, bool value) external;

    /// @dev Allows the owner to update the swap fee receiver.
    /// @param value Swap fee receiver address.
    function updateSwapFeeAddress(address value) external;

    /// @dev Allows the owner to update the magpire router core address.
    /// @param value Magpie core address.
    function updateCoreAddress(address value) external;

    /// @dev Called by the owner to pause, triggers stopped state.
    function pause() external;

    /// @dev Called by the owner to unpause, returns to normal state.
    function unpause() external;

    event Swap(
        address indexed fromAddress,
        address indexed toAddress,
        address fromAssetAddress,
        address toAssetAddress,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @dev Makes it possible to execute multiple functions in the same transaction.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);

    /// @dev Provides an external interface to estimate the gas cost of the last hop in a route.
    /// @return amountOut The amount received after swapping.
    /// @return gasUsed The cost of gas while performing the swap.
    function estimateSwapGas(bytes calldata swapArgs) external payable returns (uint256 amountOut, uint256 gasUsed);

    /// @dev Performs token swap with magpie signature.
    /// @return amountOut The amount received after swapping.
    function swapWithMagpieSignature(bytes calldata swapArgs) external payable returns (uint256 amountOut);

    /// @dev Performs token swap with a user signature.
    /// @return amountOut The amount received after swapping.
    function swapWithUserSignature(bytes calldata swapArgs) external payable returns (uint256 amountOut);
}
