// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TokenMath} from "aave-v3-origin/protocol/libraries/helpers/TokenMath.sol";

library VaultSnapshot {
    using VaultSnapshot for Data;

    uint256 public constant BPS_DIVISOR = 10_000;

    struct Data {
        uint256 lstCollateralAmount;
        uint256 lstCollateralAmountInEth;
        uint256 wethDebtAmount;
        uint256 liquidationThreshold;
        uint256 ltv;
        uint256 actualSupply;
        uint256 lstATokenBalance;
        uint256 wethDebtTokenBalance;
        uint256 lstLiquidityIndex;
        uint256 wethVariableBorrowIndex;
    }

    function netAssetValueInEth(Data memory data) internal pure returns (uint256) {
        return data.lstCollateralAmountInEth - data.wethDebtAmount;
    }

    function proportionalCollateralInLst(Data memory data, uint256 shares) internal pure returns (uint256) {
        // Rounding down rounds in the favor of the vault, decreasing the collateral available to be claimed.
        uint256 proportionalLstAToken =
            Math.mulDiv(data.lstATokenBalance, shares, data.actualSupply, Math.Rounding.Floor);

        // We use Aave's TokenMath library to get the actual LST amount from the scaled amount.
        uint256 proportionalCollateral = TokenMath.getATokenBalance(proportionalLstAToken, data.lstLiquidityIndex);

        if (proportionalCollateral == 0) {
            return 0;
        }

        // As this is queried prior to the withdraw, the lstLiquidityIndex is potentially stale.
        // To ensure vault solvency, we always subtract an additional wei.
        return proportionalCollateral - 1;
    }

    function proportionalDebtInEth(Data memory data, uint256 shares) internal pure returns (uint256) {
        // Rounding up rounds in the favor of the vault, increasing the debt owed.
        uint256 proportionalDebtToken =
            Math.mulDiv(data.wethDebtTokenBalance, shares, data.actualSupply, Math.Rounding.Ceil);

        // We use Aave's TokenMath library to get the actual debt amount from the scaled amount.
        uint256 proportionalDebt = TokenMath.getVTokenBalance(proportionalDebtToken, data.wethVariableBorrowIndex);

        if (proportionalDebt == 0) {
            return 0;
        }

        if (proportionalDebtToken == data.wethDebtTokenBalance) {
            return proportionalDebt;
        }

        // As this is queried prior to the withdraw, the wethVariableBorrowIndex is potentially stale.
        // To ensure vault solvency, we always add an additional 1 wei.
        return proportionalDebt + 1;
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
}
