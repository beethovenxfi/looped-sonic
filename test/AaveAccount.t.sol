// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AaveAccount} from "../src/libraries/AaveAccount.sol";
import {AaveAccountWrapper} from "./mocks/AaveAccountWrapper.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";

contract AaveAccountTest is Test {
    AaveAccountWrapper public wrapper;
    MockAavePool public mockPool;

    function setUp() public {
        mockPool = new MockAavePool();

        // Create test data with realistic values
        AaveAccount.Data memory testData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000, // 80% in BIPS
            ltv: 7500, // 75% in BIPS
            healthFactor: 2e18, // 2.0
            ethPrice: 2000e18, // $2000 per ETH in 18 decimals
            lstPrice: 2100e18 // $2100 per LST in 18 decimals
        });

        wrapper = new AaveAccountWrapper(testData);
    }

    function testData() public {
        AaveAccount.Data memory data = wrapper.getData();

        assertEq(data.totalCollateralBase, 1000e18, "Total collateral base should be 1000e18");
        assertEq(data.totalDebtBase, 500e18, "Total debt base should be 500e18");
        assertEq(data.availableBorrowsBase, 400e18, "Available borrows base should be 400e18");
        assertEq(data.currentLiquidationThreshold, 8000, "Current liquidation threshold should be 8000");
        assertEq(data.ltv, 7500, "LTV should be 7500");
        assertEq(data.healthFactor, 2e18, "Health factor should be 2e18");
        assertEq(data.ethPrice, 2000e18, "ETH price should be 2000e18");
        assertEq(data.lstPrice, 2100e18, "LST price should be 2100e18");
    }

    function testNetAssetValueBase() public {
        uint256 nav = wrapper.netAssetValueBase();
        assertEq(nav, 500e18, "NAV should be collateral - debt");
    }

    function testNetAssetValueInEth() public {
        uint256 navEth = wrapper.netAssetValueInEth();
        // 500e18 * 1e18 / 2000e18 = 0.25e18 (0.25 ETH)
        assertEq(navEth, 0.25e18, "NAV in ETH should be correctly converted");
    }

    function testProportionalCollateralBase() public {
        uint256 shares = 100e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalCollateral = wrapper.proportionalCollateralBase(shares, totalSupply);

        // 1000e18 * 100e18 / 1000e18 = 100e18
        assertEq(proportionalCollateral, 100e18, "Should calculate proportional collateral correctly");
    }

    function testProportionalDebtBase() public {
        uint256 shares = 200e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalDebt = wrapper.proportionalDebtBase(shares, totalSupply);

        // 500e18 * 200e18 / 1000e18 = 100e18
        assertEq(proportionalDebt, 100e18, "Should calculate proportional debt correctly");
    }

    function testProportionalCollateralInLst() public {
        uint256 shares = 100e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalLst = wrapper.proportionalCollateralInLst(shares, totalSupply);

        // proportionalCollateralBase = 100e18
        // baseToLst = 100e18 * 1e18 / 2100e18 ≈ 0.0476e18
        assertApproxEqAbs(proportionalLst, 47619047619047619, 1, "Should convert proportional collateral to LST");
    }

    function testProportionalDebtInEth() public {
        uint256 shares = 200e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalEth = wrapper.proportionalDebtInEth(shares, totalSupply);

        // proportionalDebtBase = 100e18
        // baseToEth = 100e18 * 1e18 / 2000e18 = 0.05e18
        assertEq(proportionalEth, 0.05e18, "Should convert proportional debt to ETH");
    }

    function testBaseToEth() public {
        uint256 amount = 1000e18;
        uint256 ethAmount = wrapper.baseToEth(amount);

        // 1000e18 * 1e18 / 2000e18 = 0.5e18
        assertEq(ethAmount, 0.5e18, "Should convert base amount to ETH correctly");
    }

    function testBaseToLst() public {
        uint256 amount = 2100e18;
        uint256 lstAmount = wrapper.baseToLst(amount);

        // 2100e18 * 1e18 / 2100e18 = 1e18
        assertEq(lstAmount, 1e18, "Should convert base amount to LST correctly");
    }

    function testLiquidationThresholdScaled18() public {
        uint256 threshold = wrapper.liquidationThresholdScaled18();

        // 8000 * 1e14 = 0.8e18 (80%)
        assertEq(threshold, 0.8e18, "Should scale liquidation threshold to 18 decimals");
    }

    function testInitialize() public {
        AaveAccountWrapper newWrapper = new AaveAccountWrapper(
            AaveAccount.Data({
                totalCollateralBase: 0,
                totalDebtBase: 0,
                availableBorrowsBase: 0,
                currentLiquidationThreshold: 0,
                ltv: 0,
                healthFactor: 0,
                ethPrice: 0,
                lstPrice: 0
            })
        );

        AaveAccount.Data memory data = newWrapper.getData();

        assertEq(data.totalCollateralBase, 0, "Total collateral base should be 0");
        assertEq(data.totalDebtBase, 0, "Total debt base should be 0");
        assertEq(data.availableBorrowsBase, 0, "Available borrows base should be 0");
        assertEq(data.currentLiquidationThreshold, 0, "Current liquidation threshold should be 0");

        // Set specific user account data in mock pool
        MockAavePool.UserAccountData memory mockData = MockAavePool.UserAccountData({
            totalCollateralBase: 1500e18,
            totalDebtBase: 750e18,
            availableBorrowsBase: 600e18,
            currentLiquidationThreshold: 8500,
            ltv: 8000,
            healthFactor: 2.5e18
        });

        mockPool.setUserAccountData(address(newWrapper), mockData);

        // Initialize with mock pool data
        newWrapper.initialize(mockPool, address(newWrapper), 2000e18, 2100e18);

        data = newWrapper.getData();

        assertEq(data.totalCollateralBase, 1500e18, "Total collateral base should be 1500e18");
        assertEq(data.totalDebtBase, 750e18, "Total debt base should be 750e18");
        assertEq(data.availableBorrowsBase, 600e18, "Available borrows base should be 600e18");
        assertEq(data.currentLiquidationThreshold, 8500, "Current liquidation threshold should be 8500");
        assertEq(data.ltv, 8000, "LTV should be 8000");
        assertEq(data.healthFactor, 2.5e18, "Health factor should be 2.5e18");
        assertEq(data.ethPrice, 2000e18, "ETH price should be 2000e18");
        assertEq(data.lstPrice, 2100e18, "LST price should be 2100e18");

        // Verify the data was properly initialized from the mock pool
        assertEq(newWrapper.netAssetValueBase(), 750e18, "NAV should be collateral - debt from mock data");
        assertEq(newWrapper.baseToEth(2000e18), 1e18, "ETH price should be set correctly");
        assertEq(newWrapper.baseToLst(2100e18), 1e18, "LST price should be set correctly");
        assertEq(newWrapper.liquidationThresholdScaled18(), 0.85e18, "Liquidation threshold should be from mock data");
    }

    function testEdgeCasesZeroValues() public {
        AaveAccount.Data memory zeroData = AaveAccount.Data({
            totalCollateralBase: 0,
            totalDebtBase: 0,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 0,
            ltv: 0,
            healthFactor: 0,
            ethPrice: 1e18, // Avoid division by zero
            lstPrice: 1e18 // Avoid division by zero
        });

        AaveAccountWrapper zeroWrapper = new AaveAccountWrapper(zeroData);

        assertEq(zeroWrapper.netAssetValueBase(), 0, "Zero collateral and debt should result in zero NAV");
        assertEq(
            zeroWrapper.proportionalCollateralBase(100e18, 1000e18),
            0,
            "Zero collateral should result in zero proportional"
        );
        assertEq(zeroWrapper.proportionalDebtBase(100e18, 1000e18), 0, "Zero debt should result in zero proportional");
    }

    function testProportionalCalculationsFullShares() public {
        uint256 totalSupply = 1000e18;

        // Test with 100% of shares
        uint256 fullCollateral = wrapper.proportionalCollateralBase(totalSupply, totalSupply);
        uint256 fullDebt = wrapper.proportionalDebtBase(totalSupply, totalSupply);

        assertEq(fullCollateral, 1000e18, "Full shares should equal total collateral");
        assertEq(fullDebt, 500e18, "Full shares should equal total debt");
    }

    function testUpdateData() public {
        AaveAccount.Data memory newData = AaveAccount.Data({
            totalCollateralBase: 2000e18,
            totalDebtBase: 800e18,
            availableBorrowsBase: 600e18,
            currentLiquidationThreshold: 7500,
            ltv: 7000,
            healthFactor: 3e18,
            ethPrice: 2500e18,
            lstPrice: 2600e18
        });

        wrapper.updateData(newData);

        assertEq(wrapper.netAssetValueBase(), 1200e18, "NAV should update after data change");
        assertEq(wrapper.baseToEth(2500e18), 1e18, "ETH conversion should use new price");
        assertEq(wrapper.liquidationThresholdScaled18(), 0.75e18, "Liquidation threshold should update");
    }

    function testFuzzProportionalCalculations(uint256 shares, uint256 totalSupply) public {
        vm.assume(totalSupply > 0);
        vm.assume(shares <= totalSupply);
        // Prevent overflow by limiting the size of inputs
        vm.assume(totalSupply <= type(uint128).max);
        vm.assume(shares <= type(uint128).max);

        uint256 proportionalCollateral = wrapper.proportionalCollateralBase(shares, totalSupply);
        uint256 proportionalDebt = wrapper.proportionalDebtBase(shares, totalSupply);

        // Proportional amounts should never exceed total amounts
        assertLe(proportionalCollateral, 1000e18, "Proportional collateral should not exceed total");
        assertLe(proportionalDebt, 500e18, "Proportional debt should not exceed total");

        // If shares is 0, proportional should be 0
        if (shares == 0) {
            assertEq(proportionalCollateral, 0, "Zero shares should yield zero collateral");
            assertEq(proportionalDebt, 0, "Zero shares should yield zero debt");
        }

        // If shares equals total supply, proportional should equal total
        if (shares == totalSupply) {
            assertEq(proportionalCollateral, 1000e18, "Full shares should equal total collateral");
            assertEq(proportionalDebt, 500e18, "Full shares should equal total debt");
        }
    }
}
