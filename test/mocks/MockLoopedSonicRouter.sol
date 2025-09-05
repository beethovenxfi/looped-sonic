pragma solidity ^0.8.30;

import {BaseLoopedSonicRouter} from "../../src/BaseLoopedSonicRouter.sol";
import {LoopedSonicVault} from "../../src/LoopedSonicVault.sol";

import {Test, console} from "forge-std/Test.sol";

contract MockLoopedSonicRouter is BaseLoopedSonicRouter, Test {
    uint256 public lstAmountOutOverride;

    constructor(LoopedSonicVault _vault) BaseLoopedSonicRouter(_vault) {}

    function convertWethSessionBalanceToLstSessionBalance(uint256 wethAmount) internal override returns (uint256) {
        if (lstAmountOutOverride > 0) {
            return lstAmountOutOverride;
        }

        return VAULT.stakeWeth(wethAmount);
    }

    function convertLstToWeth(uint256 lstCollateralAmount, bytes memory data) internal override returns (uint256) {
        uint256 wethAmountOut = abi.decode(data, (uint256));

        // burn the LST
        VAULT.LST().transfer(address(1), lstCollateralAmount);

        vm.deal(address(this), wethAmountOut);
        VAULT.WETH().deposit{value: wethAmountOut}();

        return wethAmountOut;
    }

    function setLstAmountOutOverride(uint256 _lstAmountOutOverride) external {
        lstAmountOutOverride = _lstAmountOutOverride;
    }
}
