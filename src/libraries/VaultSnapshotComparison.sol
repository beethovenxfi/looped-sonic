// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "./VaultSnapshot.sol";
import {console} from "forge-std/console.sol";

library VaultSnapshotComparison {
    using VaultSnapshotComparison for Data;
    using VaultSnapshot for VaultSnapshot.Data;

    uint256 public constant HEALTH_FACTOR_MARGIN = 0.000001e18;

    struct Data {
        VaultSnapshot.Data stateBefore;
        VaultSnapshot.Data stateAfter;
    }

    function navIncreaseEth(Data memory data) internal view returns (uint256) {
        return data.stateAfter.netAssetValueInEth() - data.stateBefore.netAssetValueInEth();
    }

    function navDecreaseEth(Data memory data) internal view returns (uint256) {
        return data.stateBefore.netAssetValueInEth() - data.stateAfter.netAssetValueInEth();
    }

    function checkHealthFactorAfterDeposit(Data memory data, uint256 targetHealthFactor) internal pure returns (bool) {
        if (data.stateBefore.healthFactor() < targetHealthFactor) {
            // The previous health factor is below the target, so we require that the new health factor cannot decrease
            // from it's current value
            return data.stateAfter.healthFactor() >= data.stateBefore.healthFactor()
                && data.stateAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        } else {
            // The previous health factor is above the target, we require that the health factor is within a margin of the target
            return data.stateAfter.healthFactor() >= targetHealthFactor * (1e18 - HEALTH_FACTOR_MARGIN) / 1e18
                && data.stateAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedDebtAfter =
            data.stateBefore.wethDebtAmount - data.stateBefore.proportionalDebtInEth(sharesToRedeem);

        return expectedDebtAfter == data.stateAfter.wethDebtAmount
        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei more debt
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalDebtInEth, we can
        // safely add 1 wei to the expected debt.
        || expectedDebtAfter + 1 == data.stateAfter.wethDebtAmount;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedCollateralAfter =
            data.stateBefore.lstCollateralAmount - data.stateBefore.proportionalCollateralInLst(sharesToRedeem);

        if (expectedCollateralAfter == 0) {
            return data.stateAfter.lstCollateralAmount == 0;
        }

        // When repaying debt, aave will round in it's favor, potentially leaving the vault with 1 wei less collateral
        // than expected. Since the vault rounds in it's favor in VaultSnapshot.proportionalCollateralInLst, we can
        // safely subtract 1 wei from the expected collateral.
        return expectedCollateralAfter == data.stateAfter.lstCollateralAmount
            || expectedCollateralAfter - 1 == data.stateAfter.lstCollateralAmount;
    }
}
