// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPriceCapAdapter} from "./interfaces/IPriceCapAdapter.sol";
import {IAaveCapoRateProvider} from "./interfaces/IAaveCapoRateProvider.sol";
import {ISonicStaking} from "./interfaces/ISonicStaking.sol";

contract AaveCapoRateProvider is IAaveCapoRateProvider {
    IPriceCapAdapter public immutable PRICE_CAP_ADAPTER;
    ISonicStaking public immutable LST;

    constructor(address _lst, address priceCapAdapter) {
        PRICE_CAP_ADAPTER = IPriceCapAdapter(priceCapAdapter);
        LST = ISonicStaking(_lst);
    }

    function getRate() public view returns (uint256) {
        if (isCapped()) {
            return getMaxRate();
        }

        return uint256(PRICE_CAP_ADAPTER.getRatio());
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (isCapped()) {
            return shares * getMaxRate() / 1e18;
        }

        // Since the rate is not capped, we know that the rate returned by the CAP adapter is the exact LST rate.
        // As such, we can safely use LST.convertToAssets function to convert shares to assets, avoiding additional
        // precision loss.
        return LST.convertToAssets(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        if (isCapped()) {
            return assets * 1e18 / getMaxRate();
        }

        // Since the rate is not capped, we know that the rate returned by the CAP adapter is the exact LST rate.
        // As such, we can safely use LST.convertToShares function to convert assets to shares, avoiding additional
        // precision loss.
        return LST.convertToShares(assets);
    }

    function getMaxRate() public view returns (uint256) {
        // The price CAP adapter doesn't expose the max ratio, so we need to calculate it ourselves.
        uint256 snapshotRatio = PRICE_CAP_ADAPTER.getSnapshotRatio();
        uint256 maxRatioGrowthPerSecond = PRICE_CAP_ADAPTER.getMaxRatioGrowthPerSecond();
        uint256 snapshotTimestamp = PRICE_CAP_ADAPTER.getSnapshotTimestamp();

        return snapshotRatio + maxRatioGrowthPerSecond * (block.timestamp - snapshotTimestamp);
    }

    function isCapped() public view returns (bool) {
        return PRICE_CAP_ADAPTER.isCapped();
    }
}
