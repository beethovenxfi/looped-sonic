// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseLoopedSonicRouter} from "./BaseLoopedSonicRouter.sol";
import {LoopedSonicVault} from "./LoopedSonicVault.sol";
import {IMagpieRouterV3_1} from "./interfaces/IMagpieRouterV3_1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MagpieLoopedSonicRouter is BaseLoopedSonicRouter {
    IMagpieRouterV3_1 public immutable MAGPIE_ROUTER;

    constructor(LoopedSonicVault _vault, IMagpieRouterV3_1 _magpieRouter) BaseLoopedSonicRouter(_vault) {
        MAGPIE_ROUTER = _magpieRouter;

        IERC20(address(VAULT.LST())).approve(address(MAGPIE_ROUTER), type(uint256).max);
    }

    function convertWethSessionBalanceToLstSessionBalance(uint256 wethAmount) internal override returns (uint256) {
        return VAULT.stakeWeth(wethAmount);
    }

    function convertLstToWeth(uint256 lstCollateralAmount, bytes memory data) internal override returns (uint256) {
        return MAGPIE_ROUTER.swapWithMagpieSignature(data);
    }
}
