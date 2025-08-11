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
        uint256 lstPrice;
    }

    function initialize(Data memory data, IAavePool aavePool, address vault, uint256 ethPrice, uint256 lstPrice)
        internal
        view
    {
        (
            data.totalCollateralBase,
            data.totalDebtBase,
            data.availableBorrowsBase,
            data.currentLiquidationThreshold,
            data.ltv,
            data.healthFactor
        ) = aavePool.getUserAccountData(vault);

        data.ethPrice = ethPrice;
        data.lstPrice = lstPrice;
    }

    function netAssetValueInETH(Data memory data) internal pure returns (uint256) {
        return data.baseToETH(data.totalCollateralBase - data.totalDebtBase);
    }

    function proportionalCollateralInLST(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.baseToLST(data.totalCollateralBase * shares / totalSupply);
    }

    function proportionalDebtInETH(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.baseToETH(data.totalDebtBase * shares / totalSupply);
    }

    function baseToETH(Data memory data, uint256 amount) internal pure returns (uint256) {
        return amount * 1e18 / data.ethPrice;
    }

    function baseToLST(Data memory data, uint256 amount) internal pure returns (uint256) {
        return amount * 1e18 / data.lstPrice;
    }

    function liquidationThresholdScaled18(Data memory data) internal pure returns (uint256) {
        // aave returns the liquidation threshold in BIPS
        return data.currentLiquidationThreshold * 1e14;
    }

    function isDebtInRange(Data memory data, uint256 expected, uint256 margin) internal pure returns (bool) {
        uint256 min = expected * (1e18 - margin) / 1e18;
        uint256 max = expected * (1e18 + margin) / 1e18;

        return data.totalDebtBase >= min && data.totalDebtBase <= max;
    }

    function isCollateralInRange(Data memory data, uint256 expected, uint256 margin) internal pure returns (bool) {
        uint256 min = expected * (1e18 - margin) / 1e18;
        uint256 max = expected * (1e18 + margin) / 1e18;

        return data.totalCollateralBase >= min && data.totalCollateralBase <= max;
    }
}
