// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "./VaultSnapshot.sol";
import {console} from "forge-std/console.sol";

library VaultSnapshotComparison {
    using VaultSnapshotComparison for Data;
    using VaultSnapshot for VaultSnapshot.Data;

    //uint256 public constant HEALTH_FACTOR_MARGIN = 0.000001e18;
    uint256 public constant HEALTH_FACTOR_MARGIN = 0.01e18;

    struct Data {
        VaultSnapshot.Data accountBefore;
        VaultSnapshot.Data accountAfter;
    }

    function navIncreaseEth(Data memory data) internal view returns (uint256) {
        return data.accountAfter.netAssetValueInEth() - data.accountBefore.netAssetValueInEth();
    }

    function navDecreaseEth(Data memory data) internal view returns (uint256) {
        return data.accountBefore.netAssetValueInEth() - data.accountAfter.netAssetValueInEth();
    }

    function checkHealthFactorAfterDeposit(Data memory data, uint256 targetHealthFactor) internal pure returns (bool) {
        if (data.accountBefore.healthFactor() < targetHealthFactor) {
            // The previous health factor is below the target, so we require that the new health factor cannot decrease
            // from it's current value
            return data.accountAfter.healthFactor() >= data.accountBefore.healthFactor()
                && data.accountAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        } else {
            // The previous health factor is above the target, we require that the health factor is within a margin of the target
            return data.accountAfter.healthFactor() >= targetHealthFactor * (1e18 - HEALTH_FACTOR_MARGIN) / 1e18
                && data.accountAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedDebtAfter =
            data.accountBefore.wethDebtAmount - data.accountBefore.proportionalDebtInEth(sharesToRedeem);

        return expectedDebtAfter == data.accountAfter.wethDebtAmount
        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei more debt
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalDebtInEth, we can
        // safely add 1 wei to the expected debt.
        || expectedDebtAfter + 1 == data.accountAfter.wethDebtAmount;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedCollateralAfter =
            data.accountBefore.lstCollateralAmount - data.accountBefore.proportionalCollateralInLst(sharesToRedeem);

        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei less collateral
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalCollateralInLst, we can
        // safely subtract 1 wei from the expected collateral.
        return expectedCollateralAfter == data.accountAfter.lstCollateralAmount
            || expectedCollateralAfter - 1 == data.accountAfter.lstCollateralAmount;
    }
}
