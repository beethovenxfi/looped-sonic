// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AaveAccount} from "../src/libraries/AaveAccount.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";

contract AaveAccountTest is Test {
    using AaveAccount for AaveAccount.Data;

    AaveAccount.Data public data;
    MockAavePool public mockPool;

    function setUp() public {
        mockPool = new MockAavePool();

        // Create test data with realistic values
        data = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000, // 80% in BIPS
            ltv: 7500, // 75% in BIPS
            healthFactor: 2e18, // 2.0
            ethPrice: 2000e18, // $2000 per ETH in 18 decimals
            lstPrice: 2100e18 // $2100 per LST in 18 decimals
        });
    }

    function dataValues() public {
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
        uint256 nav = data.netAssetValueBase();
        uint256 expectedNav = data.totalCollateralBase - data.totalDebtBase;
        assertEq(nav, expectedNav, "NAV should be collateral - debt");
    }

    function testNetAssetValueInEth() public {
        uint256 navEth = data.netAssetValueInEth();
        uint256 navBase = data.totalCollateralBase - data.totalDebtBase;
        uint256 expectedNavEth = (navBase * 1e18) / data.ethPrice;
        assertEq(navEth, expectedNavEth, "NAV in ETH should be correctly converted");
    }

    function testProportionalCollateralBase() public {
        uint256 shares = 100e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalCollateral = data.proportionalCollateralBase(shares, totalSupply);
        uint256 expectedProportional = (data.totalCollateralBase * shares) / totalSupply;
        assertEq(proportionalCollateral, expectedProportional, "Should calculate proportional collateral correctly");
    }

    function testProportionalDebtBase() public {
        uint256 shares = 200e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalDebt = data.proportionalDebtBase(shares, totalSupply);
        uint256 expectedProportional = (data.totalDebtBase * shares) / totalSupply;
        assertEq(proportionalDebt, expectedProportional, "Should calculate proportional debt correctly");
    }

    function testProportionalCollateralInLst() public {
        uint256 shares = 100e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalLst = data.proportionalCollateralInLst(shares, totalSupply);

        uint256 proportionalCollateralBase = (data.totalCollateralBase * shares) / totalSupply;
        uint256 expectedLst = (proportionalCollateralBase * 1e18) / data.lstPrice;
        assertApproxEqAbs(proportionalLst, expectedLst, 1, "Should convert proportional collateral to LST");
    }

    function testProportionalDebtInEth() public {
        uint256 shares = 200e18;
        uint256 totalSupply = 1000e18;
        uint256 proportionalEth = data.proportionalDebtInEth(shares, totalSupply);

        uint256 proportionalDebtBase = (data.totalDebtBase * shares) / totalSupply;
        uint256 expectedEth = (proportionalDebtBase * 1e18) / data.ethPrice;
        assertEq(proportionalEth, expectedEth, "Should convert proportional debt to ETH");
    }

    function testBaseToEth() public {
        uint256 amount = 1000e18;
        uint256 ethAmount = data.baseToEth(amount);
        uint256 expectedEth = (amount * 1e18) / data.ethPrice;
        assertEq(ethAmount, expectedEth, "Should convert base amount to ETH correctly");
    }

    function testBaseToLst() public {
        uint256 amount = 2100e18;
        uint256 lstAmount = data.baseToLst(amount);
        uint256 expectedLst = (amount * 1e18) / data.lstPrice;
        assertEq(lstAmount, expectedLst, "Should convert base amount to LST correctly");
    }

    function testLiquidationThresholdScaled18() public {
        uint256 threshold = data.liquidationThresholdScaled18();
        uint256 expectedThreshold = data.currentLiquidationThreshold * 1e14;
        assertEq(threshold, expectedThreshold, "Should scale liquidation threshold to 18 decimals");
    }

    function testInitialize() public {
        AaveAccount.Data memory localData;

        // Set specific user account data in mock pool
        MockAavePool.UserAccountData memory mockData = MockAavePool.UserAccountData({
            totalCollateralBase: 1500e18,
            totalDebtBase: 750e18,
            availableBorrowsBase: 600e18,
            currentLiquidationThreshold: 8500,
            ltv: 8000,
            healthFactor: 2.5e18
        });
        uint256 ethPrice = 2000e18;
        uint256 lstPrice = 2100e18;

        address testVault = address(this);
        mockPool.setUserAccountData(testVault, mockData);

        // Initialize with mock pool data
        localData.initialize(mockPool, testVault, ethPrice, lstPrice);

        assertEq(
            localData.totalCollateralBase, mockData.totalCollateralBase, "Total collateral base should match mock data"
        );
        assertEq(localData.totalDebtBase, mockData.totalDebtBase, "Total debt base should match mock data");
        assertEq(
            localData.availableBorrowsBase,
            mockData.availableBorrowsBase,
            "Available borrows base should match mock data"
        );
        assertEq(
            localData.currentLiquidationThreshold,
            mockData.currentLiquidationThreshold,
            "Current liquidation threshold should match mock data"
        );
        assertEq(localData.ltv, mockData.ltv, "LTV should match mock data");
        assertEq(localData.healthFactor, mockData.healthFactor, "Health factor should match mock data");
        assertEq(localData.ethPrice, ethPrice, "ETH price should be set correctly");
        assertEq(localData.lstPrice, lstPrice, "LST price should be set correctly");

        // Verify the data was properly initialized from the mock pool
        uint256 expectedNav = localData.totalCollateralBase - localData.totalDebtBase;
        assertEq(localData.netAssetValueBase(), expectedNav, "NAV should be collateral - debt from mock data");

        uint256 expectedEthConversion = (localData.ethPrice * 1e18) / localData.ethPrice;
        assertEq(localData.baseToEth(localData.ethPrice), expectedEthConversion, "ETH price should be set correctly");

        uint256 expectedLstConversion = (localData.lstPrice * 1e18) / localData.lstPrice;
        assertEq(localData.baseToLst(localData.lstPrice), expectedLstConversion, "LST price should be set correctly");
        assertEq(
            localData.liquidationThresholdScaled18(),
            mockData.currentLiquidationThreshold * 1e14,
            "Liquidation threshold should be from mock data"
        );
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

        assertEq(zeroData.netAssetValueBase(), 0, "Zero collateral and debt should result in zero NAV");
        assertEq(
            zeroData.proportionalCollateralBase(100e18, 1000e18),
            0,
            "Zero collateral should result in zero proportional"
        );
        assertEq(zeroData.proportionalDebtBase(100e18, 1000e18), 0, "Zero debt should result in zero proportional");
    }

    function testProportionalCalculationsFullShares() public {
        uint256 totalSupply = 1000e18;

        // Test with 100% of shares
        uint256 fullCollateral = data.proportionalCollateralBase(totalSupply, totalSupply);
        uint256 fullDebt = data.proportionalDebtBase(totalSupply, totalSupply);

        assertEq(fullCollateral, data.totalCollateralBase, "Full shares should equal total collateral");
        assertEq(fullDebt, data.totalDebtBase, "Full shares should equal total debt");
    }

    function testUpdateData() public {
        data = AaveAccount.Data({
            totalCollateralBase: 2000e18,
            totalDebtBase: 800e18,
            availableBorrowsBase: 600e18,
            currentLiquidationThreshold: 7500,
            ltv: 7000,
            healthFactor: 3e18,
            ethPrice: 2500e18,
            lstPrice: 2600e18
        });

        uint256 expectedUpdatedNav = data.totalCollateralBase - data.totalDebtBase;
        assertEq(data.netAssetValueBase(), expectedUpdatedNav, "NAV should update after data change");

        uint256 expectedEthConversion = (data.ethPrice * 1e18) / data.ethPrice;
        assertEq(data.baseToEth(data.ethPrice), expectedEthConversion, "ETH conversion should use new price");

        uint256 expectedThreshold = data.currentLiquidationThreshold * 1e14;
        assertEq(data.liquidationThresholdScaled18(), expectedThreshold, "Liquidation threshold should update");
    }

    function testFuzzProportionalCalculations(uint256 shares, uint256 totalSupply) public {
        vm.assume(totalSupply > 0);
        vm.assume(shares <= totalSupply);
        // Prevent overflow by limiting the size of inputs
        vm.assume(totalSupply <= type(uint128).max);
        vm.assume(shares <= type(uint128).max);

        uint256 proportionalCollateral = data.proportionalCollateralBase(shares, totalSupply);
        uint256 proportionalDebt = data.proportionalDebtBase(shares, totalSupply);

        // Proportional amounts should never exceed total amounts
        assertLe(proportionalCollateral, data.totalCollateralBase, "Proportional collateral should not exceed total");
        assertLe(proportionalDebt, data.totalDebtBase, "Proportional debt should not exceed total");

        // If shares is 0, proportional should be 0
        if (shares == 0) {
            assertEq(proportionalCollateral, 0, "Zero shares should yield zero collateral");
            assertEq(proportionalDebt, 0, "Zero shares should yield zero debt");
        }

        // If shares equals total supply, proportional should equal total
        if (shares == totalSupply) {
            assertEq(proportionalCollateral, data.totalCollateralBase, "Full shares should equal total collateral");
            assertEq(proportionalDebt, data.totalDebtBase, "Full shares should equal total debt");
        }
    }

    // EDGE CASE TESTS

    function testDivisionByZeroProtection() public {
        AaveAccount.Data memory zeroEthPriceData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 0,
            lstPrice: 2100e18
        });

        // Should revert when ethPrice is 0
        vm.expectRevert();
        zeroEthPriceData.baseToEth(1000e18);

        vm.expectRevert();
        zeroEthPriceData.netAssetValueInEth();

        vm.expectRevert();
        zeroEthPriceData.proportionalDebtInEth(100e18, 1000e18);

        AaveAccount.Data memory zeroLstPriceData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 2000e18,
            lstPrice: 0
        });

        // Should revert when lstPrice is 0
        vm.expectRevert();
        zeroLstPriceData.baseToLst(1000e18);

        vm.expectRevert();
        zeroLstPriceData.proportionalCollateralInLst(100e18, 1000e18);
    }

    function testIntegerOverflowProtection() public {
        uint256 maxCollateral = type(uint256).max;
        uint256 halfMaxDebt = type(uint256).max / 2;
        
        AaveAccount.Data memory extremeData = AaveAccount.Data({
            totalCollateralBase: maxCollateral,
            totalDebtBase: halfMaxDebt,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1e18,
            ethPrice: 1,
            lstPrice: 1
        });

        // These should handle extreme values gracefully
        uint256 nav = extremeData.netAssetValueBase();
        uint256 expectedNav = maxCollateral - halfMaxDebt;
        assertEq(nav, expectedNav, "Should handle large values in NAV calculation");

        // Test with very small price to trigger potential overflow in conversion
        uint256 baseAmount = 1e18;
        uint256 smallPrice = 1;
        extremeData.ethPrice = smallPrice;
        uint256 ethAmount = extremeData.baseToEth(baseAmount);
        uint256 expectedEthAmount = (baseAmount * 1e18) / smallPrice;
        assertEq(ethAmount, expectedEthAmount, "Should handle very small prices");
    }

    function testLiquidationScenarios() public {
        uint256 collateral = 1000e18;
        uint256 debt = collateral + 200e18; // Debt exceeds collateral
        uint256 healthFactor = 0.8e18; // Below 1.0 = liquidation
        
        AaveAccount.Data memory liquidationData = AaveAccount.Data({
            totalCollateralBase: collateral,
            totalDebtBase: debt,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: healthFactor,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        // NAV should be negative (represented as underflow)
        vm.expectRevert();
        liquidationData.netAssetValueBase();

        vm.expectRevert();
        liquidationData.netAssetValueInEth();
    }

    function testNegativeNAVScenarios() public {
        uint256 collateral = 500e18;
        uint256 debt = collateral * 2; // Debt > collateral
        uint256 healthFactor = 0.5e18;
        
        AaveAccount.Data memory negativeNavData = AaveAccount.Data({
            totalCollateralBase: collateral,
            totalDebtBase: debt,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: healthFactor,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        // Should revert on underflow when debt exceeds collateral
        vm.expectRevert();
        negativeNavData.netAssetValueBase();

        vm.expectRevert();
        negativeNavData.netAssetValueInEth();
    }

    function testRoundingErrorsInConversions() public {
        uint256 smallAmount = 1;
        uint256 ethPrice = 3e18; // Price that doesn't divide evenly
        uint256 lstPrice = 7e18;
        
        AaveAccount.Data memory roundingData = AaveAccount.Data({
            totalCollateralBase: smallAmount,
            totalDebtBase: 0,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: ethPrice,
            lstPrice: lstPrice
        });

        uint256 ethAmount = roundingData.baseToEth(smallAmount);
        uint256 expectedEthAmount = (smallAmount * 1e18) / ethPrice;
        assertEq(ethAmount, expectedEthAmount, "Small amounts should calculate correctly");

        uint256 lstAmount = roundingData.baseToLst(smallAmount);
        uint256 expectedLstAmount = (smallAmount * 1e18) / lstPrice;
        assertEq(lstAmount, expectedLstAmount, "Small amounts should calculate correctly");

        // Test with larger amount that should have remainder
        uint256 largerAmount = 5e18;
        uint256 ethAmount2 = roundingData.baseToEth(largerAmount);
        uint256 expectedEth = (largerAmount * 1e18) / ethPrice;
        assertEq(ethAmount2, expectedEth, "Should handle rounding consistently");
    }

    function testExtremePriceRatios() public {
        uint256 highPrice = type(uint128).max;
        uint256 lowPrice = 1e18;
        uint256 veryLowPrice = 1;
        
        // Test with extremely high ETH price
        AaveAccount.Data memory highEthPriceData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: highPrice,
            lstPrice: lowPrice
        });

        uint256 baseAmount = type(uint128).max;
        uint256 ethAmount = highEthPriceData.baseToEth(baseAmount);
        uint256 expectedEthAmount = (baseAmount * 1e18) / highPrice;
        assertEq(ethAmount, expectedEthAmount, "Should handle extreme price ratios");

        // Test with extremely low ETH price
        AaveAccount.Data memory lowEthPriceData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: veryLowPrice,
            lstPrice: highPrice
        });

        uint256 baseAmount2 = 1e18;
        uint256 ethAmount2 = lowEthPriceData.baseToEth(baseAmount2);
        uint256 expectedEthAmount2 = (baseAmount2 * 1e18) / veryLowPrice;
        assertEq(ethAmount2, expectedEthAmount2, "Should handle very low prices");
    }

    // FUZZ TESTS

    function testFuzzPriceConversions(uint256 amount, uint256 ethPrice, uint256 lstPrice) public {
        vm.assume(ethPrice > 0 && ethPrice <= type(uint128).max);
        vm.assume(lstPrice > 0 && lstPrice <= type(uint128).max);
        vm.assume(amount <= type(uint128).max);

        AaveAccount.Data memory fuzzData = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: ethPrice,
            lstPrice: lstPrice
        });

        uint256 ethAmount = fuzzData.baseToEth(amount);
        uint256 lstAmount = fuzzData.baseToLst(amount);

        // Basic sanity checks
        if (amount == 0) {
            assertEq(ethAmount, 0, "Zero amount should yield zero ETH");
            assertEq(lstAmount, 0, "Zero amount should yield zero LST");
        }

        // Verify conversion formula
        uint256 expectedEth = (amount * 1e18) / ethPrice;
        uint256 expectedLst = (amount * 1e18) / lstPrice;
        assertEq(ethAmount, expectedEth, "ETH conversion should match formula");
        assertEq(lstAmount, expectedLst, "LST conversion should match formula");
    }

    function testFuzzNAVCalculations(uint256 collateral, uint256 debt) public {
        vm.assume(collateral >= debt); // Avoid underflow for this test
        vm.assume(collateral <= type(uint128).max);
        vm.assume(debt <= type(uint128).max);

        AaveAccount.Data memory fuzzData = AaveAccount.Data({
            totalCollateralBase: collateral,
            totalDebtBase: debt,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        uint256 nav = fuzzData.netAssetValueBase();
        uint256 navEth = fuzzData.netAssetValueInEth();

        assertEq(nav, collateral - debt, "NAV should equal collateral minus debt");

        uint256 expectedNavEth = (nav * 1e18) / fuzzData.ethPrice;
        assertEq(navEth, expectedNavEth, "NAV in ETH should be correctly converted");
    }

    function testFuzzProportionalPrecision(uint256 shares, uint256 totalSupply, uint256 totalAmount) public {
        vm.assume(totalSupply > 0);
        vm.assume(shares <= totalSupply);
        vm.assume(totalAmount <= type(uint128).max);
        vm.assume(totalSupply <= type(uint128).max);
        vm.assume(shares <= type(uint128).max);

        AaveAccount.Data memory fuzzData = AaveAccount.Data({
            totalCollateralBase: totalAmount,
            totalDebtBase: totalAmount / 2,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        uint256 proportional = fuzzData.proportionalCollateralBase(shares, totalSupply);

        // Test mathematical properties
        if (shares == 0) {
            assertEq(proportional, 0, "Zero shares should yield zero proportional");
        }

        if (shares == totalSupply) {
            assertEq(proportional, totalAmount, "Full shares should equal total amount");
        }

        // Proportional should never exceed total
        assertLe(proportional, totalAmount, "Proportional should not exceed total");

        // Test precision: (shares * total) / totalSupply should equal proportional
        uint256 expected = (totalAmount * shares) / totalSupply;
        assertEq(proportional, expected, "Should match manual calculation");
    }
}
