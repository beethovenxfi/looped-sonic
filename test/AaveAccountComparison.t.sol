// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AaveAccountComparison} from "../src/libraries/AaveAccountComparison.sol";
import {AaveAccount} from "../src/libraries/AaveAccount.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";

contract AaveAccountComparisonTest is Test {
    using AaveAccountComparison for AaveAccountComparison.Data;
    using AaveAccount for AaveAccount.Data;

    AaveAccountComparison.Data public comparisonData;
    MockAavePool public mockPool;

    function setUp() public {
        mockPool = new MockAavePool();

        // Create test data with realistic values for before state
        AaveAccount.Data memory accountBefore = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 400e18,
            currentLiquidationThreshold: 8000, // 80% in BIPS
            ltv: 7500, // 75% in BIPS
            healthFactor: 2e18, // 2.0
            ethPrice: 2000e18, // $2000 per ETH in 18 decimals
            lstPrice: 2100e18 // $2100 per LST in 18 decimals
        });

        // Create test data for after state (improved position)
        AaveAccount.Data memory accountAfter = AaveAccount.Data({
            totalCollateralBase: 1200e18,
            totalDebtBase: 600e18,
            availableBorrowsBase: 480e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2.4e18, // Improved health factor
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        comparisonData = AaveAccountComparison.Data({accountBefore: accountBefore, accountAfter: accountAfter});
    }

    function testNavIncreaseBase() public {
        uint256 navBefore = comparisonData.accountBefore.netAssetValueBase();
        uint256 navAfter = comparisonData.accountAfter.netAssetValueBase();
        uint256 navIncrease = comparisonData.navIncreaseBase();

        assertEq(navIncrease, navAfter - navBefore, "NAV increase should be difference between after and before");
        assertEq(navIncrease, 100e18, "Expected NAV increase of 100e18");
    }

    function testNavIncreaseEth() public {
        uint256 navIncreaseBase = comparisonData.navIncreaseBase();
        uint256 navIncreaseEth = comparisonData.navIncreaseEth();
        uint256 expectedNavEth = comparisonData.accountAfter.baseToEth(navIncreaseBase);

        assertEq(navIncreaseEth, expectedNavEth, "NAV increase in ETH should be correctly converted");
    }

    function testNavDecreaseBase() public {
        // Create a scenario where NAV decreases
        AaveAccount.Data memory accountAfterDecrease = AaveAccount.Data({
            totalCollateralBase: 900e18, // Decreased collateral
            totalDebtBase: 500e18,
            availableBorrowsBase: 320e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1.6e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory decreaseData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterDecrease
        });

        uint256 navBefore = decreaseData.accountBefore.netAssetValueBase();
        uint256 navAfter = decreaseData.accountAfter.netAssetValueBase();
        uint256 navDecrease = decreaseData.navDecreaseBase();

        assertEq(navDecrease, navBefore - navAfter, "NAV decrease should be difference between before and after");
        assertEq(navDecrease, 100e18, "Expected NAV decrease of 100e18");
    }

    function testNavDecreaseEth() public {
        // Create a scenario where NAV decreases
        AaveAccount.Data memory accountAfterDecrease = AaveAccount.Data({
            totalCollateralBase: 900e18,
            totalDebtBase: 500e18,
            availableBorrowsBase: 320e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1.6e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory decreaseData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterDecrease
        });

        uint256 navDecreaseBase = decreaseData.navDecreaseBase();
        uint256 navDecreaseEth = decreaseData.navDecreaseEth();
        uint256 expectedNavEth = decreaseData.accountAfter.baseToEth(navDecreaseBase);

        assertEq(navDecreaseEth, expectedNavEth, "NAV decrease in ETH should be correctly converted");
    }

    function testCheckHealthFactorAfterDepositAboveTarget() public {
        uint256 targetHealthFactor = 2.2e18;

        // Health factor before (2.0) is below target, health factor after (2.4) is above
        bool result = comparisonData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertTrue(result, "Should pass when health factor improves from below target to above");
    }

    function testCheckHealthFactorAfterDepositBelowTargetImproves() public {
        uint256 targetHealthFactor = 3e18; // Higher than both before and after

        // Both before and after are below target, but after is higher than before
        bool result = comparisonData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertTrue(result, "Should pass when health factor improves even if still below target");
    }

    function testCheckHealthFactorAfterDepositBelowTargetDecreases() public {
        uint256 targetHealthFactor = 3e18;

        // Create scenario where health factor decreases
        AaveAccount.Data memory accountAfterWorse = AaveAccount.Data({
            totalCollateralBase: 1000e18,
            totalDebtBase: 600e18, // Increased debt
            availableBorrowsBase: 320e18,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1.6e18, // Worse health factor
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory worseData =
            AaveAccountComparison.Data({accountBefore: comparisonData.accountBefore, accountAfter: accountAfterWorse});

        bool result = worseData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertFalse(result, "Should fail when health factor decreases below margin");
    }

    function testCheckHealthFactorAfterDepositWithinMargin() public {
        uint256 targetHealthFactor = 2.4e18;

        // Health factor after exactly matches target
        bool result = comparisonData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertTrue(result, "Should pass when health factor is exactly at target");
    }

    function testCheckDebtAfterWithdraw() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Calculate expected debt after withdraw
        uint256 proportionalDebt = comparisonData.accountBefore.proportionalDebtBase(sharesToRedeem, totalSupplyBefore);
        uint256 expectedDebtAfter = comparisonData.accountBefore.totalDebtBase - proportionalDebt;

        // Create account after with expected debt
        AaveAccount.Data memory accountAfterWithdraw = comparisonData.accountAfter;
        accountAfterWithdraw.totalDebtBase = expectedDebtAfter;

        AaveAccountComparison.Data memory withdrawData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterWithdraw
        });

        bool result = withdrawData.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertTrue(result, "Should pass when debt decreases by proportional amount");
    }

    function testCheckDebtAfterWithdrawIncorrectDebt() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Keep debt unchanged (incorrect)
        bool result = comparisonData.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertFalse(result, "Should fail when debt doesn't decrease by proportional amount");
    }

    function testCheckCollateralAfterWithdraw() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Calculate expected collateral after withdraw
        uint256 proportionalCollateral =
            comparisonData.accountBefore.proportionalCollateralBase(sharesToRedeem, totalSupplyBefore);
        uint256 expectedCollateralAfter = comparisonData.accountBefore.totalCollateralBase - proportionalCollateral;

        // Create account after with expected collateral
        AaveAccount.Data memory accountAfterWithdraw = comparisonData.accountAfter;
        accountAfterWithdraw.totalCollateralBase = expectedCollateralAfter;

        AaveAccountComparison.Data memory withdrawData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterWithdraw
        });

        bool result = withdrawData.checkCollateralAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertTrue(result, "Should pass when collateral decreases by proportional amount");
    }

    function testCheckCollateralAfterWithdrawIncorrectCollateral() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Keep collateral unchanged (incorrect)
        bool result = comparisonData.checkCollateralAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertFalse(result, "Should fail when collateral doesn't decrease by proportional amount");
    }

    function testCheckNavAfterWithdraw() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Calculate expected NAV after withdraw
        uint256 navBefore = comparisonData.accountBefore.netAssetValueBase();
        uint256 navForShares = navBefore * sharesToRedeem / totalSupplyBefore;
        uint256 expectedNavAfter = navBefore - navForShares;

        // Create account after with expected NAV values
        uint256 proportionalCollateral =
            comparisonData.accountBefore.proportionalCollateralBase(sharesToRedeem, totalSupplyBefore);
        uint256 proportionalDebt = comparisonData.accountBefore.proportionalDebtBase(sharesToRedeem, totalSupplyBefore);

        AaveAccount.Data memory accountAfterWithdraw = comparisonData.accountAfter;
        accountAfterWithdraw.totalCollateralBase =
            comparisonData.accountBefore.totalCollateralBase - proportionalCollateral;
        accountAfterWithdraw.totalDebtBase = comparisonData.accountBefore.totalDebtBase - proportionalDebt;

        AaveAccountComparison.Data memory withdrawData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterWithdraw
        });

        bool result = withdrawData.checkNavAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertTrue(result, "Should pass when NAV decreases by proportional amount");
    }

    function testCheckNavAfterWithdrawIncorrectNav() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 1000e18;

        // Keep NAV unchanged (incorrect)
        bool result = comparisonData.checkNavAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        assertFalse(result, "Should fail when NAV doesn't decrease by proportional amount");
    }

    function testFullSharesWithdraw() public {
        uint256 totalSupplyBefore = 1000e18;
        uint256 sharesToRedeem = totalSupplyBefore; // 100% of shares

        // Create account after with zero values (full withdrawal)
        AaveAccount.Data memory accountAfterFullWithdraw = AaveAccount.Data({
            totalCollateralBase: 0,
            totalDebtBase: 0,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: type(uint256).max, // Max health factor with no debt
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory fullWithdrawData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterFullWithdraw
        });

        bool debtResult = fullWithdrawData.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        bool collateralResult = fullWithdrawData.checkCollateralAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        bool navResult = fullWithdrawData.checkNavAfterWithdraw(sharesToRedeem, totalSupplyBefore);

        assertTrue(debtResult, "Full withdrawal should remove all debt");
        assertTrue(collateralResult, "Full withdrawal should remove all collateral");
        assertTrue(navResult, "Full withdrawal should result in zero NAV");
    }

    function testFuzzNavCalculations(
        uint256 collateralBefore,
        uint256 debtBefore,
        uint256 collateralAfter,
        uint256 debtAfter
    ) public {
        vm.assume(collateralBefore >= debtBefore); // Avoid underflow
        vm.assume(collateralAfter >= debtAfter); // Avoid underflow
        vm.assume(collateralBefore <= type(uint128).max);
        vm.assume(debtBefore <= type(uint128).max);
        vm.assume(collateralAfter <= type(uint128).max);
        vm.assume(debtAfter <= type(uint128).max);

        AaveAccount.Data memory fuzzAccountBefore = AaveAccount.Data({
            totalCollateralBase: collateralBefore,
            totalDebtBase: debtBefore,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccount.Data memory fuzzAccountAfter = AaveAccount.Data({
            totalCollateralBase: collateralAfter,
            totalDebtBase: debtAfter,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 2e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory fuzzData =
            AaveAccountComparison.Data({accountBefore: fuzzAccountBefore, accountAfter: fuzzAccountAfter});

        uint256 navBefore = fuzzAccountBefore.netAssetValueBase();
        uint256 navAfter = fuzzAccountAfter.netAssetValueBase();

        if (navAfter >= navBefore) {
            uint256 navIncrease = fuzzData.navIncreaseBase();
            assertEq(navIncrease, navAfter - navBefore, "NAV increase should be correctly calculated");
        } else {
            uint256 navDecrease = fuzzData.navDecreaseBase();
            assertEq(navDecrease, navBefore - navAfter, "NAV decrease should be correctly calculated");
        }
    }

    function testFuzzProportionalWithdrawCalculations(uint256 shares, uint256 totalSupply) public {
        vm.assume(totalSupply > 0);
        vm.assume(shares <= totalSupply);
        vm.assume(totalSupply <= type(uint128).max);
        vm.assume(shares <= type(uint128).max);

        uint256 proportionalDebt = comparisonData.accountBefore.proportionalDebtBase(shares, totalSupply);
        uint256 proportionalCollateral = comparisonData.accountBefore.proportionalCollateralBase(shares, totalSupply);

        // Proportional amounts should never exceed totals
        assertLe(
            proportionalDebt, comparisonData.accountBefore.totalDebtBase, "Proportional debt should not exceed total"
        );
        assertLe(
            proportionalCollateral,
            comparisonData.accountBefore.totalCollateralBase,
            "Proportional collateral should not exceed total"
        );

        // Test edge cases
        if (shares == 0) {
            assertEq(proportionalDebt, 0, "Zero shares should yield zero debt");
            assertEq(proportionalCollateral, 0, "Zero shares should yield zero collateral");
        }

        if (shares == totalSupply) {
            assertEq(
                proportionalDebt, comparisonData.accountBefore.totalDebtBase, "Full shares should equal total debt"
            );
            assertEq(
                proportionalCollateral,
                comparisonData.accountBefore.totalCollateralBase,
                "Full shares should equal total collateral"
            );
        }
    }

    function testFuzzHealthFactorChecks(
        uint256 targetHealthFactor,
        uint256 healthFactorBefore,
        uint256 healthFactorAfter
    ) public {
        vm.assume(targetHealthFactor > 0 && targetHealthFactor <= type(uint128).max);
        vm.assume(healthFactorBefore > 0 && healthFactorBefore <= type(uint128).max);
        vm.assume(healthFactorAfter > 0 && healthFactorAfter <= type(uint128).max);

        AaveAccount.Data memory fuzzAccountBefore = comparisonData.accountBefore;
        fuzzAccountBefore.healthFactor = healthFactorBefore;

        AaveAccount.Data memory fuzzAccountAfter = comparisonData.accountAfter;
        fuzzAccountAfter.healthFactor = healthFactorAfter;

        AaveAccountComparison.Data memory fuzzData =
            AaveAccountComparison.Data({accountBefore: fuzzAccountBefore, accountAfter: fuzzAccountAfter});

        bool result = fuzzData.checkHealthFactorAfterDeposit(targetHealthFactor);

        uint256 margin = AaveAccountComparison.HEALTH_FACTOR_MARGIN;

        if (healthFactorBefore < targetHealthFactor) {
            // Should pass if health factor improved or stayed within margin
            bool expectedResult = healthFactorAfter >= healthFactorBefore * (1e18 - margin) / 1e18;
            assertEq(result, expectedResult, "Health factor check should match expected result for below target case");
        } else {
            // Should pass if within margin of target
            bool expectedResult = healthFactorAfter >= targetHealthFactor * (1e18 - margin) / 1e18
                && healthFactorAfter <= targetHealthFactor * (1e18 + margin) / 1e18;
            assertEq(result, expectedResult, "Health factor check should match expected result for above target case");
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testZeroTotalSupplyWithdraw() public {
        uint256 sharesToRedeem = 100e18;
        uint256 totalSupplyBefore = 0;

        vm.expectRevert();
        comparisonData.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore);
    }

    function testZeroSharesWithdraw() public {
        uint256 sharesToRedeem = 0;
        uint256 totalSupplyBefore = 1000e18;

        AaveAccount.Data memory accountAfterZeroWithdraw = comparisonData.accountBefore;

        AaveAccountComparison.Data memory zeroWithdrawData = AaveAccountComparison.Data({
            accountBefore: comparisonData.accountBefore,
            accountAfter: accountAfterZeroWithdraw
        });

        bool debtResult = zeroWithdrawData.checkDebtAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        bool collateralResult = zeroWithdrawData.checkCollateralAfterWithdraw(sharesToRedeem, totalSupplyBefore);
        bool navResult = zeroWithdrawData.checkNavAfterWithdraw(sharesToRedeem, totalSupplyBefore);

        assertTrue(debtResult, "Zero shares withdrawal should pass debt check");
        assertTrue(collateralResult, "Zero shares withdrawal should pass collateral check");
        assertTrue(navResult, "Zero shares withdrawal should pass NAV check");
    }

    function testZeroHealthFactorScenarios() public {
        uint256 targetHealthFactor = 2e18;

        AaveAccount.Data memory accountWithZeroHealthFactor = comparisonData.accountBefore;
        accountWithZeroHealthFactor.healthFactor = 0;

        AaveAccount.Data memory accountAfterImproved = comparisonData.accountAfter;
        accountAfterImproved.healthFactor = 1.5e18;

        AaveAccountComparison.Data memory zeroHealthData =
            AaveAccountComparison.Data({accountBefore: accountWithZeroHealthFactor, accountAfter: accountAfterImproved});

        bool result = zeroHealthData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertTrue(result, "Should pass when health factor improves from 0");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testZeroPriceScenarios() public {
        AaveAccount.Data memory accountWithZeroEthPrice = comparisonData.accountBefore;
        accountWithZeroEthPrice.ethPrice = 0;

        AaveAccount.Data memory accountAfterWithZeroEthPrice = comparisonData.accountAfter;
        accountAfterWithZeroEthPrice.ethPrice = 0;

        AaveAccountComparison.Data memory zeroPriceData = AaveAccountComparison.Data({
            accountBefore: accountWithZeroEthPrice,
            accountAfter: accountAfterWithZeroEthPrice
        });

        vm.expectRevert();
        zeroPriceData.navIncreaseEth();
    }

    // EDGE CASE TESTS: Overflow/Underflow
    function testMaxUint256CollateralAndDebt() public {
        AaveAccount.Data memory accountMaxBefore = AaveAccount.Data({
            totalCollateralBase: type(uint256).max - 1e18,
            totalDebtBase: type(uint256).max - 2e18,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccount.Data memory accountMaxAfter = AaveAccount.Data({
            totalCollateralBase: type(uint256).max,
            totalDebtBase: type(uint256).max - 2e18,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 1e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory maxData =
            AaveAccountComparison.Data({accountBefore: accountMaxBefore, accountAfter: accountMaxAfter});

        uint256 navIncrease = maxData.navIncreaseBase();
        assertEq(navIncrease, 1e18, "Should handle max values correctly");
    }

    function testNearOverflowPriceConversion() public {
        AaveAccount.Data memory accountHighPrice = comparisonData.accountBefore;
        accountHighPrice.ethPrice = type(uint128).max;

        AaveAccount.Data memory accountAfterHighPrice = comparisonData.accountAfter;
        accountAfterHighPrice.ethPrice = type(uint128).max;

        AaveAccountComparison.Data memory highPriceData =
            AaveAccountComparison.Data({accountBefore: accountHighPrice, accountAfter: accountAfterHighPrice});

        uint256 navIncreaseEth = highPriceData.navIncreaseEth();
        console.log("navIncreaseEth", navIncreaseEth);
        assertTrue(navIncreaseEth > 0, "Should handle high prices without overflow");
    }

    // EDGE CASE TESTS: Precision Loss
    function testSmallSharesLargeTotalSupply() public {
        uint256 sharesToRedeem = 1;
        uint256 totalSupplyBefore = type(uint128).max;

        uint256 proportionalDebt = comparisonData.accountBefore.proportionalDebtBase(sharesToRedeem, totalSupplyBefore);
        uint256 proportionalCollateral =
            comparisonData.accountBefore.proportionalCollateralBase(sharesToRedeem, totalSupplyBefore);

        assertEq(proportionalDebt, 0, "Very small share should round down to zero debt");
        assertEq(proportionalCollateral, 0, "Very small share should round down to zero collateral");
    }

    function testPrecisionLossInHealthFactorMargin() public {
        uint256 targetHealthFactor = 3; // Very small target
        uint256 healthFactorBefore = 2;
        uint256 healthFactorAfter = 2;

        AaveAccount.Data memory accountBefore = comparisonData.accountBefore;
        accountBefore.healthFactor = healthFactorBefore;

        AaveAccount.Data memory accountAfter = comparisonData.accountAfter;
        accountAfter.healthFactor = healthFactorAfter;

        AaveAccountComparison.Data memory precisionData =
            AaveAccountComparison.Data({accountBefore: accountBefore, accountAfter: accountAfter});

        bool result = precisionData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertFalse(result, "Should handle precision loss in small health factor calculations");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testUnderwaterPosition() public {
        AaveAccount.Data memory underwaterAccount = AaveAccount.Data({
            totalCollateralBase: 500e18,
            totalDebtBase: 1000e18, // Debt > Collateral
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 0.5e18, // Below 1.0
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccount.Data memory improvedAccount = AaveAccount.Data({
            totalCollateralBase: 800e18,
            totalDebtBase: 1000e18,
            availableBorrowsBase: 0,
            currentLiquidationThreshold: 8000,
            ltv: 7500,
            healthFactor: 0.8e18,
            ethPrice: 2000e18,
            lstPrice: 2100e18
        });

        AaveAccountComparison.Data memory underwaterData =
            AaveAccountComparison.Data({accountBefore: underwaterAccount, accountAfter: improvedAccount});

        vm.expectRevert();
        underwaterData.navIncreaseBase();
    }

    function testLiquidatableHealthFactor() public {
        uint256 targetHealthFactor = 2e18;

        AaveAccount.Data memory liquidatableAccount = comparisonData.accountBefore;
        liquidatableAccount.healthFactor = 0.9e18; // Below 1.0, liquidatable

        AaveAccount.Data memory improvedAccount = comparisonData.accountAfter;
        improvedAccount.healthFactor = 1.1e18; // Above 1.0 but below target

        AaveAccountComparison.Data memory liquidatableData =
            AaveAccountComparison.Data({accountBefore: liquidatableAccount, accountAfter: improvedAccount});

        bool result = liquidatableData.checkHealthFactorAfterDeposit(targetHealthFactor);
        assertTrue(result, "Should pass when improving from liquidatable state");
    }

    // FUZZ TESTS: Price Variations
    function testFuzzPriceVariations(uint256 ethPrice, uint256 lstPrice) public {
        vm.assume(ethPrice > 0 && ethPrice <= type(uint128).max);
        vm.assume(lstPrice > 0 && lstPrice <= type(uint128).max);

        AaveAccount.Data memory accountWithFuzzPrices = comparisonData.accountBefore;
        accountWithFuzzPrices.ethPrice = ethPrice;
        accountWithFuzzPrices.lstPrice = lstPrice;

        AaveAccount.Data memory accountAfterWithFuzzPrices = comparisonData.accountAfter;
        accountAfterWithFuzzPrices.ethPrice = ethPrice;
        accountAfterWithFuzzPrices.lstPrice = lstPrice;

        AaveAccountComparison.Data memory priceData =
            AaveAccountComparison.Data({accountBefore: accountWithFuzzPrices, accountAfter: accountAfterWithFuzzPrices});

        uint256 navIncreaseBase = priceData.navIncreaseBase();
        uint256 navIncreaseEth = priceData.navIncreaseEth();

        uint256 expectedNavEth = accountAfterWithFuzzPrices.baseToEth(navIncreaseBase);
        assertEq(navIncreaseEth, expectedNavEth, "Price conversion should be consistent");
    }

    // FUZZ TESTS: Margin Boundary Testing
    function testFuzzMarginBoundaries(uint256 targetHealthFactor, uint256 marginOffset) public {
        vm.assume(targetHealthFactor > 1e17 && targetHealthFactor <= type(uint64).max);
        vm.assume(marginOffset <= AaveAccountComparison.HEALTH_FACTOR_MARGIN);

        uint256 margin = AaveAccountComparison.HEALTH_FACTOR_MARGIN;
        uint256 healthFactorBefore = targetHealthFactor - 1e16; // Slightly below target
        uint256 healthFactorAfter = targetHealthFactor * (1e18 - margin + marginOffset) / 1e18;

        AaveAccount.Data memory accountBefore = comparisonData.accountBefore;
        accountBefore.healthFactor = healthFactorBefore;

        AaveAccount.Data memory accountAfter = comparisonData.accountAfter;
        accountAfter.healthFactor = healthFactorAfter;

        AaveAccountComparison.Data memory marginData =
            AaveAccountComparison.Data({accountBefore: accountBefore, accountAfter: accountAfter});

        bool result = marginData.checkHealthFactorAfterDeposit(targetHealthFactor);
        bool expectedResult = marginOffset > 0;
        assertEq(result, expectedResult, "Margin boundary should be respected");
    }

    // FUZZ TESTS: Rounding Errors in Proportional Calculations
    function testFuzzRoundingErrorsProportional(uint256 shares, uint256 totalSupply, uint256 totalAmount) public {
        vm.assume(totalSupply > 0 && totalSupply <= type(uint64).max);
        vm.assume(shares <= totalSupply);
        vm.assume(totalAmount <= type(uint64).max);
        vm.assume(totalAmount > 0);

        uint256 proportional = (totalAmount * shares) / totalSupply;
        uint256 remainder = (totalAmount * shares) % totalSupply;

        // Check for rounding consistency
        if (remainder > 0) {
            assertLt(proportional, totalAmount, "Proportional amount should be less than total when rounding down");
        } else {
            assertEq((totalAmount * shares) / totalSupply, proportional, "Should be exact when no remainder");
        }

        // Edge case: when shares == totalSupply, proportional should equal totalAmount
        if (shares == totalSupply) {
            assertEq(proportional, totalAmount, "Full shares should equal total amount");
        }
    }

    // FUZZ TESTS: State Transition Scenarios
    function testFuzzStateTransitions(uint256 collateralChange, uint256 debtChange, bool isIncrease) public {
        vm.assume(collateralChange <= 1000e18);
        vm.assume(debtChange <= 500e18);

        uint256 newCollateral = isIncrease
            ? comparisonData.accountBefore.totalCollateralBase + collateralChange
            : comparisonData.accountBefore.totalCollateralBase - collateralChange;

        uint256 newDebt = isIncrease
            ? comparisonData.accountBefore.totalDebtBase + debtChange
            : comparisonData.accountBefore.totalDebtBase - debtChange;

        vm.assume(newCollateral >= newDebt); // Avoid underwater positions

        AaveAccount.Data memory transitionAccount = comparisonData.accountAfter;
        transitionAccount.totalCollateralBase = newCollateral;
        transitionAccount.totalDebtBase = newDebt;

        AaveAccountComparison.Data memory transitionData =
            AaveAccountComparison.Data({accountBefore: comparisonData.accountBefore, accountAfter: transitionAccount});

        uint256 navBefore = comparisonData.accountBefore.netAssetValueBase();
        uint256 navAfter = transitionAccount.netAssetValueBase();

        if (navAfter >= navBefore) {
            uint256 navIncrease = transitionData.navIncreaseBase();
            assertEq(
                navIncrease, navAfter - navBefore, "NAV increase should be calculated correctly for state transitions"
            );
        } else {
            uint256 navDecrease = transitionData.navDecreaseBase();
            assertEq(
                navDecrease, navBefore - navAfter, "NAV decrease should be calculated correctly for state transitions"
            );
        }
    }
}
