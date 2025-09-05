// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveCapoRateProvider} from "../src/AaveCapoRateProvider.sol";
import {MockPriceCapAdapter} from "./mocks/MockPriceCapAdapter.sol";

contract AaveCapoRateProviderTest is LoopedSonicVaultBase {
    AaveCapoRateProvider public localAaveCapoRateProvider;
    MockPriceCapAdapter public priceCapAdapter;

    function setUp() public override {
        super.setUp();
        priceCapAdapter = new MockPriceCapAdapter();
        localAaveCapoRateProvider = new AaveCapoRateProvider(address(LST), address(priceCapAdapter));
    }

    function testGetRateWhenNotCapped() public {
        priceCapAdapter.setIsCapped(false);
        priceCapAdapter.setRatio(1.5e18);

        uint256 rate = localAaveCapoRateProvider.getRate();
        assertEq(rate, 1.5e18);
    }

    function testGetRateWhenCapped() public {
        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(1e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp - 100);
        priceCapAdapter.setMaxRatioGrowthPerSecond(1e15);

        uint256 expectedMaxRate = 1e18 + (1e15 * 100);
        uint256 rate = localAaveCapoRateProvider.getRate();
        assertEq(rate, expectedMaxRate);
    }

    function testGetMaxRate() public {
        uint256 snapshotRatio = 1.2e18;
        uint256 maxRatioGrowthPerSecond = 5e14;
        uint256 timeElapsed = 200;

        priceCapAdapter.setSnapshotRatio(snapshotRatio);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp - timeElapsed);
        priceCapAdapter.setMaxRatioGrowthPerSecond(maxRatioGrowthPerSecond);

        uint256 expectedMaxRate = snapshotRatio + (maxRatioGrowthPerSecond * timeElapsed);
        uint256 maxRate = localAaveCapoRateProvider.getMaxRate();
        assertEq(maxRate, expectedMaxRate);
    }

    function testIsCapped() public {
        priceCapAdapter.setIsCapped(false);
        assertFalse(localAaveCapoRateProvider.isCapped());

        priceCapAdapter.setIsCapped(true);
        assertTrue(localAaveCapoRateProvider.isCapped());
    }

    function testConvertToAssetsWhenNotCapped() public {
        uint256 shares = 1e18;
        uint256 expectedAssets = 1.5e18;

        priceCapAdapter.setIsCapped(false);
        vm.mockCall(
            address(LST), abi.encodeWithSignature("convertToAssets(uint256)", shares), abi.encode(expectedAssets)
        );

        uint256 assets = localAaveCapoRateProvider.convertToAssets(shares);
        assertEq(assets, expectedAssets);
    }

    function testConvertToAssetsWhenCapped() public {
        uint256 shares = 2e18;
        uint256 maxRate = 1.5e18;

        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(1e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp - 100);
        priceCapAdapter.setMaxRatioGrowthPerSecond(5e15);

        uint256 expectedAssets = shares * maxRate / 1e18;
        uint256 actualMaxRate = 1e18 + (5e15 * 100);
        uint256 expectedAssetsCalculated = shares * actualMaxRate / 1e18;

        uint256 assets = localAaveCapoRateProvider.convertToAssets(shares);
        assertEq(assets, expectedAssetsCalculated);
    }

    function testConvertToSharesWhenNotCapped() public {
        uint256 assets = 2e18;
        uint256 expectedShares = 1.5e18;

        priceCapAdapter.setIsCapped(false);
        vm.mockCall(
            address(LST), abi.encodeWithSignature("convertToShares(uint256)", assets), abi.encode(expectedShares)
        );

        uint256 shares = localAaveCapoRateProvider.convertToShares(assets);
        assertEq(shares, expectedShares);
    }

    function testConvertToSharesWhenCapped() public {
        uint256 assets = 3e18;

        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(1e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp - 50);
        priceCapAdapter.setMaxRatioGrowthPerSecond(2e15);

        uint256 actualMaxRate = 1e18 + (2e15 * 50);
        uint256 expectedShares = assets * 1e18 / actualMaxRate;

        uint256 shares = localAaveCapoRateProvider.convertToShares(assets);
        assertEq(shares, expectedShares);
    }

    function testConstructorSetsCorrectAddresses() public {
        assertEq(address(localAaveCapoRateProvider.PRICE_CAP_ADAPTER()), address(priceCapAdapter));
        assertEq(address(localAaveCapoRateProvider.LST()), address(LST));
    }

    function testGetMaxRateWithZeroTimeElapsed() public {
        uint256 snapshotRatio = 1.1e18;

        priceCapAdapter.setSnapshotRatio(snapshotRatio);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp);
        priceCapAdapter.setMaxRatioGrowthPerSecond(1e15);

        uint256 maxRate = localAaveCapoRateProvider.getMaxRate();
        assertEq(maxRate, snapshotRatio);
    }

    function testGetRateReflectsPriceCapAdapterState() public {
        priceCapAdapter.setIsCapped(false);
        priceCapAdapter.setRatio(2.5e18);

        uint256 rate1 = localAaveCapoRateProvider.getRate();
        assertEq(rate1, 2.5e18);

        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(1e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp - 1000);
        priceCapAdapter.setMaxRatioGrowthPerSecond(1e12);

        uint256 rate2 = localAaveCapoRateProvider.getRate();
        assertEq(rate2, 1e18 + (1e12 * 1000));
    }

    function testConvertToAssetsEdgeCases() public {
        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(1e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp);
        priceCapAdapter.setMaxRatioGrowthPerSecond(0);

        uint256 assets = localAaveCapoRateProvider.convertToAssets(1e18);
        assertEq(assets, 1e18);

        assets = localAaveCapoRateProvider.convertToAssets(0);
        assertEq(assets, 0);
    }

    function testConvertToSharesEdgeCases() public {
        priceCapAdapter.setIsCapped(true);
        priceCapAdapter.setSnapshotRatio(2e18);
        priceCapAdapter.setSnapshotTimestamp(block.timestamp);
        priceCapAdapter.setMaxRatioGrowthPerSecond(0);

        uint256 shares = localAaveCapoRateProvider.convertToShares(2e18);
        assertEq(shares, 1e18);

        shares = localAaveCapoRateProvider.convertToShares(0);
        assertEq(shares, 0);
    }
}
