// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseLoopedSonicRouter} from "../../src/BaseLoopedSonicRouter.sol";
import {LoopedSonicVault} from "../../src/LoopedSonicVault.sol";
import {IBalancerVault} from "../../src/interfaces/IBalancerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BalancerLoopedSonicRouter is BaseLoopedSonicRouter {
    using SafeERC20 for IERC20;

    IBalancerVault public immutable BALANCER_VAULT;

    constructor(LoopedSonicVault _vault, IBalancerVault _balancerVault) BaseLoopedSonicRouter(_vault) {
        BALANCER_VAULT = _balancerVault;

        IERC20(address(VAULT.WETH())).approve(address(BALANCER_VAULT), type(uint256).max);
        IERC20(address(VAULT.LST())).approve(address(BALANCER_VAULT), type(uint256).max);
    }

    function convertWethSessionBalanceToLstSessionBalance(uint256 wethAmount) internal override returns (uint256) {
        return VAULT.stakeWeth(wethAmount);
    }

    function convertLstToWeth(uint256 lstCollateralAmount, bytes memory data) internal override returns (uint256) {
        return BALANCER_VAULT.swap(
            IBalancerVault.SingleSwap({
                poolId: 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: address(VAULT.LST()),
                assetOut: address(VAULT.WETH()),
                amount: lstCollateralAmount,
                userData: ""
            }),
            IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            0,
            type(uint256).max
        );
    }
}
