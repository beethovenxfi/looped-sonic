// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "./VaultSnapshot.sol";
import {console} from "forge-std/console.sol";

library VaultSnapshotComparison {
    using VaultSnapshotComparison for Data;
    using VaultSnapshot for VaultSnapshot.Data;

    uint256 public constant HEALTH_FACTOR_MARGIN = 0.000001e18;

    struct Data {
        VaultSnapshot.Data dataBefore;
        VaultSnapshot.Data dataAfter;
    }

    function navIncreaseEth(Data memory data) internal view returns (uint256) {
        return data.dataAfter.netAssetValueInEth() - data.dataBefore.netAssetValueInEth();
    }

    function navDecreaseEth(Data memory data) internal view returns (uint256) {
        return data.dataBefore.netAssetValueInEth() - data.dataAfter.netAssetValueInEth();
    }

    function checkHealthFactorAfterDeposit(Data memory data, uint256 targetHealthFactor) internal pure returns (bool) {
        if (data.dataBefore.healthFactor() < targetHealthFactor) {
            // The previous health factor is below the target, so we require that the new health factor cannot decrease
            // from it's current value
            return data.dataAfter.healthFactor() >= data.dataBefore.healthFactor()
                && data.dataAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        } else {
            // The previous health factor is above the target, we require that the health factor is within a margin of the target
            return data.dataAfter.healthFactor() >= targetHealthFactor * (1e18 - HEALTH_FACTOR_MARGIN) / 1e18
                && data.dataAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedDebtAfter =
            data.dataBefore.wethDebtAmount - data.dataBefore.proportionalDebtInEth(sharesToRedeem);

        return expectedDebtAfter == data.dataAfter.wethDebtAmount
        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei more debt
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalDebtInEth, we can
        // safely add 1 wei to the expected debt.
        || expectedDebtAfter + 1 == data.dataAfter.wethDebtAmount;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedCollateralAfter =
            data.dataBefore.lstCollateralAmount - data.dataBefore.proportionalCollateralInLst(sharesToRedeem);

        if (expectedCollateralAfter == 0) {
            return data.dataAfter.lstCollateralAmount == 0;
        }

        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei less collateral
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalCollateralInLst, we can
        // safely subtract 1 wei from the expected collateral.
        return expectedCollateralAfter == data.dataAfter.lstCollateralAmount
            || expectedCollateralAfter - 1 == data.dataAfter.lstCollateralAmount;
    }
}
