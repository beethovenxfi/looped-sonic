// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {VaultSnapshotComparison} from "../src/libraries/VaultSnapshotComparison.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {console} from "forge-std/console.sol";

contract VaultSnapshotComparisonTest is Test {
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;
    using VaultSnapshot for VaultSnapshot.Data;

    VaultSnapshotComparison.Data private comparison;

    uint256 private constant BASE_COLLATERAL_AMOUNT = 100e18;
    uint256 private constant BASE_COLLATERAL_IN_ETH = 100e18;
    uint256 private constant BASE_DEBT_AMOUNT = 50e18;
    uint256 private constant BASE_TOTAL_SUPPLY = 1000e18;
    uint16 private constant LIQUIDATION_THRESHOLD = 8500;
    uint16 private constant LTV = 8000;
    uint256 private constant TARGET_HEALTH_FACTOR = 2e18;

    function setUp() public {
        VaultSnapshot.Data memory beforeSnapshot = VaultSnapshot.Data({
            lstCollateralAmount: BASE_COLLATERAL_AMOUNT,
            lstCollateralAmountInEth: BASE_COLLATERAL_IN_ETH,
            wethDebtAmount: BASE_DEBT_AMOUNT,
            liquidationThreshold: LIQUIDATION_THRESHOLD,
            ltv: LTV,
            vaultTotalSupply: BASE_TOTAL_SUPPLY
        });

        VaultSnapshot.Data memory afterSnapshot = VaultSnapshot.Data({
            lstCollateralAmount: BASE_COLLATERAL_AMOUNT,
            lstCollateralAmountInEth: BASE_COLLATERAL_IN_ETH,
            wethDebtAmount: BASE_DEBT_AMOUNT,
            liquidationThreshold: LIQUIDATION_THRESHOLD,
            ltv: LTV,
            vaultTotalSupply: BASE_TOTAL_SUPPLY
        });

        comparison = VaultSnapshotComparison.Data({stateBefore: beforeSnapshot, stateAfter: afterSnapshot});
    }

    function testNavIncreaseEth() public {
        comparison.stateAfter.lstCollateralAmountInEth = BASE_COLLATERAL_IN_ETH + 20e18;

        uint256 increase = comparison.navIncreaseEth();
        assertEq(increase, 20e18);
    }

    function testNavIncreaseEthWithDebtIncrease() public {
        comparison.stateAfter.lstCollateralAmountInEth = BASE_COLLATERAL_IN_ETH + 30e18;
        comparison.stateAfter.wethDebtAmount = BASE_DEBT_AMOUNT + 10e18;

        uint256 expectedIncrease = 30e18 - 10e18;
        uint256 increase = comparison.navIncreaseEth();
        assertEq(increase, expectedIncrease);
    }

    function testNavDecreaseEth() public {
        comparison.stateAfter.lstCollateralAmountInEth = BASE_COLLATERAL_IN_ETH - 15e18;

        uint256 decrease = comparison.navDecreaseEth();
        assertEq(decrease, 15e18);
    }

    function testNavDecreaseEthWithDebtDecrease() public {
        comparison.stateAfter.lstCollateralAmountInEth = BASE_COLLATERAL_IN_ETH - 20e18;
        comparison.stateAfter.wethDebtAmount = BASE_DEBT_AMOUNT - 5e18;

        uint256 expectedDecrease = 20e18 - 5e18;
        uint256 decrease = comparison.navDecreaseEth();
        assertEq(decrease, expectedDecrease);
    }

    function testCheckHealthFactorAfterDepositWithLowHealthFactor() public {
        uint256 lowHealthFactor = 1.5e18;
        comparison.stateBefore.wethDebtAmount = comparison.stateBefore.lstCollateralAmountInEth
            * comparison.stateBefore.liquidationThresholdScaled18() / lowHealthFactor;

        comparison.stateAfter.wethDebtAmount = comparison.stateBefore.wethDebtAmount - 5e18;

        bool result = comparison.checkHealthFactorAfterDeposit(TARGET_HEALTH_FACTOR);
        assertTrue(result, "Health factor check should pass when HF increases from low value");
    }

    function testCheckHealthFactorAfterDepositWithLowHealthFactorDecrease() public {
        uint256 lowHealthFactor = 1.5e18;
        comparison.stateBefore.wethDebtAmount = comparison.stateBefore.lstCollateralAmountInEth
            * comparison.stateBefore.liquidationThresholdScaled18() / lowHealthFactor;

        comparison.stateAfter.wethDebtAmount = comparison.stateBefore.wethDebtAmount + 5e18;

        bool result = comparison.checkHealthFactorAfterDeposit(TARGET_HEALTH_FACTOR);
        assertFalse(result, "Health factor check should fail when HF decreases from low value");
    }

    function testCheckHealthFactorAfterDepositWithHighHealthFactorWithinMargin() public {
        uint256 highHealthFactor = 3e18;
        comparison.stateBefore.wethDebtAmount = comparison.stateBefore.lstCollateralAmountInEth
            * comparison.stateBefore.liquidationThresholdScaled18() / highHealthFactor;

        uint256 targetDebt = comparison.stateAfter.lstCollateralAmountInEth
            * comparison.stateAfter.liquidationThresholdScaled18() / TARGET_HEALTH_FACTOR;
        comparison.stateAfter.wethDebtAmount = targetDebt;

        bool result = comparison.checkHealthFactorAfterDeposit(TARGET_HEALTH_FACTOR);
        assertTrue(result, "Health factor check should pass when within margin of target");
    }

    function testCheckHealthFactorAfterDepositWithHighHealthFactorOutsideMargin() public {
        uint256 highHealthFactor = 3e18;
        comparison.stateBefore.wethDebtAmount = comparison.stateBefore.lstCollateralAmountInEth
            * comparison.stateBefore.liquidationThresholdScaled18() / highHealthFactor;

        uint256 marginFactor = 1e18 + VaultSnapshotComparison.HEALTH_FACTOR_MARGIN + 1;
        uint256 targetDebt = comparison.stateAfter.lstCollateralAmountInEth
            * comparison.stateAfter.liquidationThresholdScaled18() / (TARGET_HEALTH_FACTOR * marginFactor / 1e18);
        comparison.stateAfter.wethDebtAmount = targetDebt;

        bool result = comparison.checkHealthFactorAfterDeposit(TARGET_HEALTH_FACTOR);
        assertFalse(result, "Health factor check should fail when outside margin of target");
    }

    function testCheckDebtAfterWithdrawExactMatch() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        comparison.stateAfter.wethDebtAmount = BASE_DEBT_AMOUNT - expectedDebtReduction;

        bool result = comparison.checkDebtAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Debt check should pass with exact expected debt amount");
    }

    function testCheckDebtAfterWithdrawWithOneWeiTolerance() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        comparison.stateAfter.wethDebtAmount = BASE_DEBT_AMOUNT - expectedDebtReduction + 1;

        bool result = comparison.checkDebtAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Debt check should pass with 1 wei tolerance for Aave rounding");
    }

    function testCheckDebtAfterWithdrawWithTooHighDebt() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        comparison.stateAfter.wethDebtAmount = BASE_DEBT_AMOUNT - expectedDebtReduction + 2;

        bool result = comparison.checkDebtAfterWithdraw(sharesToRedeem);
        assertFalse(result, "Debt check should fail with debt higher than 1 wei tolerance");
    }

    function testCheckCollateralAfterWithdrawExactMatch() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);
        comparison.stateAfter.lstCollateralAmount = BASE_COLLATERAL_AMOUNT - expectedCollateralReduction;

        bool result = comparison.checkCollateralAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Collateral check should pass with exact expected collateral amount");
    }

    function testCheckCollateralAfterWithdrawWithOneWeiTolerance() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);
        comparison.stateAfter.lstCollateralAmount = BASE_COLLATERAL_AMOUNT - expectedCollateralReduction - 1;

        bool result = comparison.checkCollateralAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Collateral check should pass with 1 wei tolerance for Aave rounding");
    }

    function testCheckCollateralAfterWithdrawWithTooLowCollateral() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);
        comparison.stateAfter.lstCollateralAmount = BASE_COLLATERAL_AMOUNT - expectedCollateralReduction - 2;

        bool result = comparison.checkCollateralAfterWithdraw(sharesToRedeem);
        assertFalse(result, "Collateral check should fail with collateral lower than 1 wei tolerance");
    }

    function testFuzzNavIncreaseEth(
        uint256 beforeColInEth,
        uint256 beforeDebt,
        uint256 afterColInEth,
        uint256 afterDebt
    ) public {
        beforeColInEth = bound(beforeColInEth, 0, type(uint128).max);
        beforeDebt = bound(beforeDebt, 0, beforeColInEth);
        afterColInEth = bound(afterColInEth, 0, type(uint128).max);
        afterDebt = bound(afterDebt, 0, afterColInEth);

        vm.assume(afterColInEth - afterDebt >= beforeColInEth - beforeDebt);

        comparison.stateBefore.lstCollateralAmountInEth = beforeColInEth;
        comparison.stateBefore.wethDebtAmount = beforeDebt;
        comparison.stateAfter.lstCollateralAmountInEth = afterColInEth;
        comparison.stateAfter.wethDebtAmount = afterDebt;

        uint256 expected = (afterColInEth - afterDebt) - (beforeColInEth - beforeDebt);
        uint256 result = comparison.navIncreaseEth();
        assertEq(result, expected);
    }

    function testFuzzNavDecreaseEth(
        uint256 beforeColInEth,
        uint256 beforeDebt,
        uint256 afterColInEth,
        uint256 afterDebt
    ) public {
        beforeColInEth = bound(beforeColInEth, 0, type(uint128).max);
        beforeDebt = bound(beforeDebt, 0, beforeColInEth);
        afterColInEth = bound(afterColInEth, 0, type(uint128).max);
        afterDebt = bound(afterDebt, 0, afterColInEth);

        vm.assume(beforeColInEth - beforeDebt >= afterColInEth - afterDebt);

        comparison.stateBefore.lstCollateralAmountInEth = beforeColInEth;
        comparison.stateBefore.wethDebtAmount = beforeDebt;
        comparison.stateAfter.lstCollateralAmountInEth = afterColInEth;
        comparison.stateAfter.wethDebtAmount = afterDebt;

        uint256 expected = (beforeColInEth - beforeDebt) - (afterColInEth - afterDebt);
        uint256 result = comparison.navDecreaseEth();
        assertEq(result, expected);
    }

    function testFuzzCheckDebtAfterWithdraw(uint256 initialDebt, uint256 totalSupply, uint256 sharesToRedeem) public {
        initialDebt = bound(initialDebt, 1, type(uint128).max);
        totalSupply = bound(totalSupply, 1, type(uint128).max);
        sharesToRedeem = bound(sharesToRedeem, 1, totalSupply);

        comparison.stateBefore.wethDebtAmount = initialDebt;
        comparison.stateBefore.vaultTotalSupply = totalSupply;
        comparison.stateAfter.vaultTotalSupply = totalSupply;

        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        comparison.stateAfter.wethDebtAmount = initialDebt - expectedDebtReduction;

        assertTrue(comparison.checkDebtAfterWithdraw(sharesToRedeem));

        if (expectedDebtReduction < initialDebt) {
            comparison.stateAfter.wethDebtAmount = initialDebt - expectedDebtReduction + 1;
            assertTrue(comparison.checkDebtAfterWithdraw(sharesToRedeem));

            comparison.stateAfter.wethDebtAmount = initialDebt - expectedDebtReduction + 2;
            assertFalse(comparison.checkDebtAfterWithdraw(sharesToRedeem));
        }
    }

    function testFuzzCheckCollateralAfterWithdraw(
        uint256 initialCollateral,
        uint256 totalSupply,
        uint256 sharesToRedeem
    ) public {
        initialCollateral = bound(initialCollateral, 1, type(uint128).max);
        totalSupply = bound(totalSupply, 1, type(uint128).max);
        sharesToRedeem = bound(sharesToRedeem, 1, totalSupply);

        comparison.stateBefore.lstCollateralAmount = initialCollateral;
        comparison.stateBefore.vaultTotalSupply = totalSupply;
        comparison.stateAfter.vaultTotalSupply = totalSupply;

        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);
        comparison.stateAfter.lstCollateralAmount = initialCollateral - expectedCollateralReduction;

        assertTrue(comparison.checkCollateralAfterWithdraw(sharesToRedeem));

        // simulate aave rounding in it's favor
        if (initialCollateral > expectedCollateralReduction) {
            comparison.stateAfter.lstCollateralAmount = initialCollateral - expectedCollateralReduction - 1;
            assertTrue(comparison.checkCollateralAfterWithdraw(sharesToRedeem));
        }
    }

    function testHealthFactorMarginConstant() public view {
        assertEq(VaultSnapshotComparison.HEALTH_FACTOR_MARGIN, 0.000001e18);
    }

    function testEdgeCaseZeroShares() public {
        uint256 sharesToRedeem = 0;

        assertTrue(comparison.checkDebtAfterWithdraw(sharesToRedeem));
        assertTrue(comparison.checkCollateralAfterWithdraw(sharesToRedeem));
    }

    function testEdgeCaseMaxShares() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY;

        comparison.stateAfter.wethDebtAmount = 0;
        comparison.stateAfter.lstCollateralAmount = 0;

        assertTrue(comparison.checkDebtAfterWithdraw(sharesToRedeem));
        assertTrue(comparison.checkCollateralAfterWithdraw(sharesToRedeem));
    }

    function testHealthFactorCheckExactTargetFromBelow() public {
        uint256 belowTargetHF = TARGET_HEALTH_FACTOR - 0.1e18;
        comparison.stateBefore.wethDebtAmount = comparison.stateBefore.lstCollateralAmountInEth
            * comparison.stateBefore.liquidationThresholdScaled18() / belowTargetHF;

        uint256 targetDebt = comparison.stateAfter.lstCollateralAmountInEth
            * comparison.stateAfter.liquidationThresholdScaled18() / TARGET_HEALTH_FACTOR;
        comparison.stateAfter.wethDebtAmount = targetDebt;

        bool result = comparison.checkHealthFactorAfterDeposit(TARGET_HEALTH_FACTOR);
        assertTrue(result, "Should pass when reaching exact target from below");
    }
}
