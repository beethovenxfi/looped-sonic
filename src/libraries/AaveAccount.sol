// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAavePool} from "../interfaces/IAavePool.sol";

library AaveAccount {
    using AaveAccount for Data;

    struct Data {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
        uint256 ethPrice;
    }

    function initialize(Data memory data, IAavePool aavePool, address vault, uint256 ethPrice) internal view {
        (
            data.totalCollateralBase,
            data.totalDebtBase,
            data.availableBorrowsBase,
            data.currentLiquidationThreshold,
            data.ltv,
            data.healthFactor
        ) = aavePool.getUserAccountData(vault);

        data.ethPrice = ethPrice;
    }

    function netAssetValueInETH(Data memory data) internal pure returns (uint256) {
        return data.baseToETH(data.totalCollateralBase - data.totalDebtBase);
    }

    function baseToETH(Data memory data, uint256 amount) internal pure returns (uint256) {
        return amount * 1e18 / data.ethPrice;
    }

    function liquidationThresholdScaled18(Data memory data) internal pure returns (uint256) {
        // aave returns the liquidation threshold in BIPS
        return data.currentLiquidationThreshold * 1e14;
    }
}
