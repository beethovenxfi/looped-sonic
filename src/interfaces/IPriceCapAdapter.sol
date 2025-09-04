// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IPriceCapAdapter {
    /**
     * @notice Maximum percentage factor (100.00%)
     */
    function PERCENTAGE_FACTOR() external view returns (uint256);

    /**
     * @notice Minimal time while ratio should not overflow, in years
     */
    function MINIMAL_RATIO_INCREASE_LIFETIME() external view returns (uint256);

    /**
     * @notice Number of seconds per year (365 days)
     */
    function SECONDS_PER_YEAR() external view returns (uint256);

    /**
     * @notice Ratio feed for (LST_ASSET / BASE_ASSET) pair
     */
    function RATIO_PROVIDER() external view returns (address);

    /**
     * @notice Number of decimals in the output of this price adapter
     */
    function DECIMALS() external view returns (uint8);

    /**
     * @notice Number of decimals for (lst asset / underlying asset) ratio
     */
    function RATIO_DECIMALS() external view returns (uint8);

    /**
     * @notice Minimum time (in seconds) that should have passed from the snapshot timestamp to the current block.timestamp
     */
    function MINIMUM_SNAPSHOT_DELAY() external view returns (uint48);

    /**
     * @notice Returns the current exchange ratio of lst to the underlying(base) asset
     */
    function getRatio() external view returns (int256);

    /**
     * @notice Returns the latest snapshot ratio
     */
    function getSnapshotRatio() external view returns (uint256);

    /**
     * @notice Returns the latest snapshot timestamp
     */
    function getSnapshotTimestamp() external view returns (uint256);

    /**
     * @notice Returns the max ratio growth per second
     */
    function getMaxRatioGrowthPerSecond() external view returns (uint256);

    /**
     * @notice Returns the max yearly ratio growth
     */
    function getMaxYearlyGrowthRatePercent() external view returns (uint256);

    /**
     * @notice Returns if the price is currently capped
     */
    function isCapped() external view returns (bool);
}
