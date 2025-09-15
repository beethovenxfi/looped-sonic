// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "./VaultSnapshot.sol";
import {TokenMath} from "aave-v3-origin/protocol/libraries/helpers/TokenMath.sol";

library VaultSnapshotComparison {
    using VaultSnapshotComparison for Data;
    using VaultSnapshot for VaultSnapshot.Data;

    uint256 public constant HEALTH_FACTOR_MARGIN_LOWER = 0.00000001e18;
    // Since the LST has a min deposit of 0.01 ETH, there are instances where the deposit loop ends up with slightly
    // less than 0.01 ETH available to borrow. This margin accounts for that on the upper bound.
    uint256 public constant HEALTH_FACTOR_MARGIN_UPPER = 0.0001e18;

    struct Data {
        VaultSnapshot.Data stateBefore;
        VaultSnapshot.Data stateAfter;
    }

    function navIncreaseEth(Data memory data) internal pure returns (uint256) {
        return data.stateAfter.netAssetValueInEth() - data.stateBefore.netAssetValueInEth();
    }

    function navDecreaseEth(Data memory data) internal pure returns (uint256) {
        return data.stateBefore.netAssetValueInEth() - data.stateAfter.netAssetValueInEth();
    }

    function checkHealthFactorAfterDeposit(Data memory data, uint256 targetHealthFactor) internal pure returns (bool) {
        if (data.stateBefore.healthFactor() < targetHealthFactor) {
            // The previous health factor is below the target, so we require that the new health factor cannot decrease
            // from it's current value
            return data.stateAfter.healthFactor() >= data.stateBefore.healthFactor()
                && data.stateAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN_UPPER) / 1e18;
        } else {
            // The previous health factor is above the target, we require that the health factor is within a margin of
            // the target
            return data.stateAfter.healthFactor() >= targetHealthFactor * (1e18 - HEALTH_FACTOR_MARGIN_LOWER) / 1e18
                && data.stateAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN_UPPER) / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedWethDebtTokenBurned = TokenMath.getVTokenBurnScaledAmount(
            data.stateBefore.proportionalDebtInEth(sharesToRedeem), data.stateAfter.wethVariableBorrowIndex
        );

        if (data.stateBefore.wethDebtTokenBalance <= expectedWethDebtTokenBurned) {
            return data.stateAfter.wethDebtTokenBalance == 0;
        }

        return
            data.stateAfter.wethDebtTokenBalance == data.stateBefore.wethDebtTokenBalance - expectedWethDebtTokenBurned;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem) internal pure returns (bool) {
        uint256 expectedLstATokenBurned = TokenMath.getATokenBurnScaledAmount(
            data.stateBefore.proportionalCollateralInLst(sharesToRedeem), data.stateAfter.lstLiquidityIndex
        );

        if (data.stateBefore.lstATokenBalance <= expectedLstATokenBurned) {
            return data.stateAfter.lstATokenBalance == 0;
        }

        return data.stateAfter.lstATokenBalance == data.stateBefore.lstATokenBalance - expectedLstATokenBurned;
    }
}
