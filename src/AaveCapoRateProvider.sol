// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAavePool} from "./interfaces/IAavePool.sol";
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
        if (PRICE_CAP_ADAPTER.isCapped()) {
            return getMaxRate();
        }

        return uint256(PRICE_CAP_ADAPTER.getRatio());
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (PRICE_CAP_ADAPTER.isCapped()) {
            return shares * getMaxRate() / 1e18;
        }

        return LST.convertToAssets(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        if (PRICE_CAP_ADAPTER.isCapped()) {
            return assets * 1e18 / getMaxRate();
        }

        return LST.convertToShares(assets);
    }

    function getMaxRate() public view returns (uint256) {
        // The price CAP adapter doesn't expose the max ratio, so we need to calculate it ourselves.
        uint256 snapshotRatio = PRICE_CAP_ADAPTER.getSnapshotRatio();
        uint256 maxRatioGrowthPerSecond = PRICE_CAP_ADAPTER.getMaxRatioGrowthPerSecond();
        uint256 snapshotTimestamp = PRICE_CAP_ADAPTER.getSnapshotTimestamp();

        return snapshotRatio + maxRatioGrowthPerSecond * (block.timestamp - snapshotTimestamp);
    }
}
