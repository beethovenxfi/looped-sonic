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

    function netAssetValueInEth(Data memory data) internal pure returns (uint256) {
        return data.baseToEth(data.totalCollateralBase - data.totalDebtBase);
    }

    function proportionalCollateralBase(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.totalCollateralBase * shares / totalSupply;
    }

    function proportionalDebtBase(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.totalDebtBase * shares / totalSupply;
    }

    function proportionalCollateralInLst(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.baseToLst(data.proportionalCollateralBase(shares, totalSupply));
    }

    function proportionalDebtInEth(Data memory data, uint256 shares, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        return data.baseToEth(data.proportionalDebtBase(shares, totalSupply));
    }

    function baseToEth(Data memory data, uint256 amount) internal pure returns (uint256) {
        return amount * 1e18 / data.ethPrice;
    }

    function baseToLst(Data memory data, uint256 amount) internal pure returns (uint256) {
        return amount * 1e18 / data.lstPrice;
    }

    function liquidationThresholdScaled18(Data memory data) internal pure returns (uint256) {
        // aave returns the liquidation threshold in BIPS
        return data.currentLiquidationThreshold * 1e14;
    }
}
