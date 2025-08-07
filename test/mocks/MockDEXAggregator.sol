// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDEXAggregator} from "../../src/interfaces/IDEXAggregator.sol";

contract MockDEXAggregator is IDEXAggregator {
    uint256 public constant RATE = 1e18; // 1:1 exchange rate
    
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        bytes calldata
    ) external override returns (uint256 amountOut) {
        amountOut = amountIn; // 1:1 for simplicity
        
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
    
    function querySwap(address, address, uint256 amountIn) 
        external 
        pure 
        override 
        returns (uint256 amountOut) 
    {
        amountOut = amountIn; // 1:1 for simplicity
    }
}