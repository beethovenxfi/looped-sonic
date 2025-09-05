// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPriceCapAdapter} from "../../src/interfaces/IPriceCapAdapter.sol";

contract MockPriceCapAdapter is IPriceCapAdapter {
    uint256 public constant PERCENTAGE_FACTOR = 10000;
    uint256 public constant MINIMAL_RATIO_INCREASE_LIFETIME = 10;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    address public constant RATIO_PROVIDER = address(0x123);
    uint8 public constant DECIMALS = 18;
    uint8 public constant RATIO_DECIMALS = 18;
    uint48 public constant MINIMUM_SNAPSHOT_DELAY = 3600;

    int256 private _ratio;
    uint256 private _snapshotRatio;
    uint256 private _snapshotTimestamp;
    uint256 private _maxRatioGrowthPerSecond;
    uint256 private _maxYearlyGrowthRatePercent;
    bool private _isCapped;

    constructor() {
        _ratio = 1e18;
        _snapshotRatio = 1e18;
        _snapshotTimestamp = block.timestamp;
        _maxRatioGrowthPerSecond = 1e15;
        _maxYearlyGrowthRatePercent = 500;
        _isCapped = false;
    }

    function getRatio() external view returns (int256) {
        return _ratio;
    }

    function getSnapshotRatio() external view returns (uint256) {
        return _snapshotRatio;
    }

    function getSnapshotTimestamp() external view returns (uint256) {
        return _snapshotTimestamp;
    }

    function getMaxRatioGrowthPerSecond() external view returns (uint256) {
        return _maxRatioGrowthPerSecond;
    }

    function getMaxYearlyGrowthRatePercent() external view returns (uint256) {
        return _maxYearlyGrowthRatePercent;
    }

    function isCapped() external view returns (bool) {
        return _isCapped;
    }

    function setRatio(int256 value) external {
        _ratio = value;
    }

    function setSnapshotRatio(uint256 value) external {
        _snapshotRatio = value;
    }

    function setSnapshotTimestamp(uint256 value) external {
        _snapshotTimestamp = value;
    }

    function setMaxRatioGrowthPerSecond(uint256 value) external {
        _maxRatioGrowthPerSecond = value;
    }

    function setMaxYearlyGrowthRatePercent(uint256 value) external {
        _maxYearlyGrowthRatePercent = value;
    }

    function setIsCapped(bool value) external {
        _isCapped = value;
    }
}
