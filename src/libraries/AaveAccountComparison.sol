// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AaveAccount} from "./AaveAccount.sol";

library AaveAccountComparison {
    using AaveAccountComparison for Data;
    using AaveAccount for AaveAccount.Data;

    struct Data {
        AaveAccount.Data accountBefore;
        AaveAccount.Data accountAfter;
    }

    function navIncreaseBase(Data memory data) internal pure returns (uint256) {
        return data.accountAfter.netAssetValueBase() - data.accountBefore.netAssetValueBase();
    }

    function navIncreaseEth(Data memory data) internal pure returns (uint256) {
        return data.accountAfter.baseToEth(data.navIncreaseBase());
    }

    function navDecreaseBase(Data memory data) internal pure returns (uint256) {
        return data.accountBefore.netAssetValueBase() - data.accountAfter.netAssetValueBase();
    }

    function navDecreaseEth(Data memory data) internal pure returns (uint256) {
        return data.accountAfter.baseToEth(data.navDecreaseBase());
    }

    function checkHealthFactorAfterDeposit(Data memory data, uint256 targetHealthFactor) internal pure returns (bool) {
        if (data.accountBefore.healthFactor < targetHealthFactor) {
            // The current health factor is below the target, so we require that the health factor cannot decrease
            // from it's current value
            return data.accountAfter.healthFactor >= data.accountBefore.healthFactor * 0.999e18 / 1e18;
        } else {
            // The current health factor is above the target, so we require that the health factor stays above the
            // target
            //TODO: health factor should be greater than target but less than a margin
            return data.accountAfter.healthFactor >= targetHealthFactor * 0.999e18 / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem, uint256 totalSupplyBefore)
        internal
        pure
        returns (bool)
    {
        uint256 expectedDebtAfter = data.accountBefore.totalDebtBase
            - data.accountBefore.proportionalDebtBase(sharesToRedeem, totalSupplyBefore);

        return expectedDebtAfter == data.accountAfter.totalDebtBase;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem, uint256 totalSupplyBefore)
        internal
        pure
        returns (bool)
    {
        uint256 expectedCollateralAfter = data.accountBefore.totalCollateralBase
            - data.accountBefore.proportionalCollateralBase(sharesToRedeem, totalSupplyBefore);

        return expectedCollateralAfter == data.accountAfter.totalCollateralBase;
    }

    function checkNavAfterWithdraw(Data memory data, uint256 sharesToRedeem, uint256 totalSupplyBefore)
        internal
        pure
        returns (bool)
    {
        uint256 navBefore = data.accountBefore.netAssetValueBase();
        uint256 navForShares = navBefore * sharesToRedeem / totalSupplyBefore;
        uint256 expectedNavAfter = navBefore - navForShares;

        return data.accountAfter.netAssetValueBase() == expectedNavAfter;
    }
}
