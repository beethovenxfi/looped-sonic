// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library VaultSnapshot {
    using VaultSnapshot for Data;

    uint256 public constant RAY = 1e27;
    uint256 public constant BPS_DIVISOR = 10_000;

    struct Data {
        uint256 lstCollateralAmount;
        uint256 lstCollateralAmountInEth;
        uint256 wethDebtAmount;
        uint256 liquidationThreshold;
        uint256 ltv;
        uint256 vaultTotalSupply;
        uint256 lstATokenBalance;
        uint256 wethDebtTokenBalance;
        uint256 lstLiquidityIndex;
        uint256 wethVariableBorrowIndex;
    }

    function netAssetValueInEth(Data memory data) internal pure returns (uint256) {
        return data.lstCollateralAmountInEth - data.wethDebtAmount;
    }

    function proportionalCollateralInLst(Data memory data, uint256 shares) internal pure returns (uint256) {
        // This represents the amount of collateral in LST that the user can withdraw when redeeming their shares.
        // Rounding down rounds in the favor of the vault, decreasing the collateral available to be claimed.
        uint256 proportionalCollateral =
            Math.mulDiv(data.lstCollateralAmount, shares, data.vaultTotalSupply, Math.Rounding.Floor);

        uint256 liquidityIndexMaxError = data.lstLiquidityIndexMaxError();

        if (proportionalCollateral <= liquidityIndexMaxError) {
            return 0;
        }

        // Aave's precision loss is bounded by the liquidity index. To ensure the vault ends up with at least as much
        // collateral as it expects, we subtract the max error from the proportional collateral, decreasing the
        // collateral the user can withdraw.
        return proportionalCollateral - liquidityIndexMaxError;
    }

    function proportionalDebtInEth(Data memory data, uint256 shares) internal pure returns (uint256) {
        // This represents the amount of debt in ETH that the user needs to repay when redeeming their shares.
        // Rounding up rounds in the favor of the vault, increasing the debt owed.
        uint256 proportionalDebt = Math.mulDiv(data.wethDebtAmount, shares, data.vaultTotalSupply, Math.Rounding.Ceil);

        // Aave's precision loss is bounded by the variable borrow index. To ensure the vault ends up with no more debt
        // than it expects, we add the max error to the proportional debt, increasing the debt the user must repay.
        return proportionalDebt + data.wethVariableBorrowIndexMaxError();
    }

    function availableBorrowsInEth(Data memory data) internal pure returns (uint256) {
        if (data.lstCollateralAmountInEth == 0) {
            return 0;
        }

        uint256 maxDebt = data.lstCollateralAmountInEth * data.ltv / BPS_DIVISOR;

        if (data.wethDebtAmount >= maxDebt) {
            return 0;
        }

        return maxDebt - data.wethDebtAmount;
    }

    function liquidationThresholdScaled18(Data memory data) internal pure returns (uint256) {
        return data.liquidationThreshold * 1e14;
    }

    function healthFactor(Data memory data) internal pure returns (uint256) {
        return data.wethDebtAmount == 0
            ? type(uint256).max
            : data.lstCollateralAmountInEth * data.liquidationThresholdScaled18() / data.wethDebtAmount;
    }

    function borrowAmountForLoopInEth(Data memory data, uint256 targetHealthFactor) internal pure returns (uint256) {
        // Aaave's base currency is using 8 decimals, we account for that here, leaving a buffer
        uint256 maxBorrowAmount = data.availableBorrowsInEth() * 0.999999e18 / 1e18;
        uint256 currentHealthFactor = data.healthFactor();

        if (currentHealthFactor < targetHealthFactor || maxBorrowAmount == 0) {
            return 0;
        }

        if (data.wethDebtAmount > 0) {
            // We calculate the amount we'd need to borrow to reach the target health factor
            // considering we'd deposit that amount back into the pool as collateral
            uint256 targetAmount = ((currentHealthFactor - targetHealthFactor) * data.wethDebtAmount)
                / (targetHealthFactor - data.liquidationThresholdScaled18());

            if (targetAmount < maxBorrowAmount) {
                // In this instance we'll exceed the target health factor if we borrow the max amount,
                // so we return the target amount
                return targetAmount;
            }
        }

        return maxBorrowAmount;
    }

    // Aave's precision loss is bounded by the liquidity index, rounded up.
    // With a liquidity index of 10e27, the max error is 10 wei.

    function lstLiquidityIndexMaxError(Data memory data) internal pure returns (uint256) {
        // On withdraws, the max error is calculated prior to the aave market update, so the liquidity index value
        // could be stale. To ensure we always round in the favor of the vault, we add 1 to the max error.
        return data.lstLiquidityIndex / RAY + 1;
    }

    function wethVariableBorrowIndexMaxError(Data memory data) internal pure returns (uint256) {
        // On withdraws, the max error is calculated prior to the aave market update, so the variable borrow index
        // value could be stale. To ensure we always round in the favor of the vault, we add 1 to the max error.
        return data.wethVariableBorrowIndex / RAY + 1;
    }
}
