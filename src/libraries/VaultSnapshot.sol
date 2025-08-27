// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISonicStaking} from "../interfaces/ISonicStaking.sol";

library VaultSnapshot {
    using VaultSnapshot for Data;

    struct Data {
        uint256 lstCollateralAmount;
        uint256 wethDebtAmount;
        uint256 liquidationThreshold;
        uint256 ltv;
        uint256 vaultTotalSupply;
        ISonicStaking lst;
    }

    function netAssetValueInEth(Data memory data) internal view returns (uint256) {
        return data.lstToEth(data.lstCollateralAmount) - data.wethDebtAmount;
    }

    function proportionalCollateralInLst(Data memory data, uint256 shares) internal pure returns (uint256) {
        // This represents the amount of collateral in LST that the user can withdraw when redeeming their shares.
        // Rounding down rounds in the favor of the vault, decreasing the collateral available to be claimed.
        return data.lstCollateralAmount * shares / data.vaultTotalSupply;
    }

    function proportionalDebtInEth(Data memory data, uint256 shares) internal pure returns (uint256) {
        // This represents the amount of debt in ETH that the user needs to repay when redeeming their shares.
        // Rounding up rounds in the favor of the vault, increasing the debt owed.
        return Math.mulDiv(data.wethDebtAmount, shares, data.vaultTotalSupply, Math.Rounding.Ceil);
    }

    function availableBorrowsInEth(Data memory data) internal pure returns (uint256) {
        if (data.lstCollateralAmount == 0) {
            return 0;
        }

        return data.lstCollateralAmount * data.ltv / 10_000 - data.wethDebtAmount;
    }

    function ethToLst(Data memory data, uint256 amount) internal view returns (uint256) {
        return data.lst.convertToShares(amount);
    }

    function lstToEth(Data memory data, uint256 amount) internal view returns (uint256) {
        return data.lst.convertToAssets(amount);
    }

    function liquidationThresholdScaled18(Data memory data) internal pure returns (uint256) {
        return data.liquidationThreshold * 1e14;
    }

    function healthFactor(Data memory data) internal pure returns (uint256) {
        return data.wethDebtAmount == 0
            ? type(uint256).max
            : data.lstCollateralAmount * data.liquidationThresholdScaled18() / data.wethDebtAmount;
    }
}
