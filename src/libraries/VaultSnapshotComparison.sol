// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultSnapshot} from "./VaultSnapshot.sol";
import {TokenMath} from "aave-v3-origin/protocol/libraries/helpers/TokenMath.sol";

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
            // The previous health factor is above the target, we require that the health factor is within a margin of
            // the target
            return data.stateAfter.healthFactor() >= targetHealthFactor * (1e18 - HEALTH_FACTOR_MARGIN) / 1e18
                && data.stateAfter.healthFactor() <= targetHealthFactor * (1e18 + HEALTH_FACTOR_MARGIN) / 1e18;
        }
    }

    function checkDebtAfterWithdraw(Data memory data, uint256 sharesToRedeem, uint256 wethVariableBorrowIndex)
        internal
        pure
        returns (bool)
    {
        uint256 expectedWethDebtTokenBurned = TokenMath.getVTokenBurnScaledAmount(
            data.stateBefore.proportionalDebtInEth(sharesToRedeem), wethVariableBorrowIndex
        );

        return
            data.stateAfter.wethDebtTokenBalance == data.stateBefore.wethDebtTokenBalance - expectedWethDebtTokenBurned;
    }

    function checkCollateralAfterWithdraw(Data memory data, uint256 sharesToRedeem, uint256 lstLiquidityIndex)
        internal
        pure
        returns (bool)
    {
        uint256 expectedLstATokenBurned = TokenMath.getATokenBurnScaledAmount(
            data.stateBefore.proportionalCollateralInLst(sharesToRedeem), lstLiquidityIndex
        );

        return data.stateAfter.lstATokenBalance == data.stateBefore.lstATokenBalance - expectedLstATokenBurned;
    }
}
