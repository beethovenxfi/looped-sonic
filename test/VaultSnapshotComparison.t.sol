// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {VaultSnapshotComparison} from "../src/libraries/VaultSnapshotComparison.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {console} from "forge-std/console.sol";
import {TokenMath} from "aave-v3-origin/protocol/libraries/helpers/TokenMath.sol";

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
    uint256 private constant WETH_VARIABLE_BORROW_INDEX = 1e27;
    uint256 private constant LST_LIQUIDITY_INDEX = 1e27;
    uint256 private constant LST_A_TOKEN_BALANCE = 100e18;
    uint256 private constant WETH_DEBT_TOKEN_BALANCE = 50e18;

    function setUp() public {
        VaultSnapshot.Data memory beforeSnapshot = VaultSnapshot.Data({
            lstCollateralAmount: BASE_COLLATERAL_AMOUNT,
            lstCollateralAmountInEth: BASE_COLLATERAL_IN_ETH,
            wethDebtAmount: BASE_DEBT_AMOUNT,
            liquidationThreshold: LIQUIDATION_THRESHOLD,
            ltv: LTV,
            vaultTotalSupply: BASE_TOTAL_SUPPLY,
            lstATokenBalance: LST_A_TOKEN_BALANCE,
            wethDebtTokenBalance: WETH_DEBT_TOKEN_BALANCE,
            lstLiquidityIndex: LST_LIQUIDITY_INDEX,
            wethVariableBorrowIndex: WETH_VARIABLE_BORROW_INDEX
        });

        VaultSnapshot.Data memory afterSnapshot = VaultSnapshot.Data({
            lstCollateralAmount: BASE_COLLATERAL_AMOUNT,
            lstCollateralAmountInEth: BASE_COLLATERAL_IN_ETH,
            wethDebtAmount: BASE_DEBT_AMOUNT,
            liquidationThreshold: LIQUIDATION_THRESHOLD,
            ltv: LTV,
            vaultTotalSupply: BASE_TOTAL_SUPPLY,
            lstATokenBalance: LST_A_TOKEN_BALANCE,
            wethDebtTokenBalance: WETH_DEBT_TOKEN_BALANCE,
            lstLiquidityIndex: LST_LIQUIDITY_INDEX,
            wethVariableBorrowIndex: WETH_VARIABLE_BORROW_INDEX
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

        uint256 expectedDebtTokenReduction =
            TokenMath.getVTokenBurnScaledAmount(expectedDebtReduction, WETH_VARIABLE_BORROW_INDEX);

        comparison.stateAfter.wethDebtTokenBalance = WETH_DEBT_TOKEN_BALANCE - expectedDebtTokenReduction;

        bool result = comparison.checkDebtAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Debt check should pass with exact expected debt amount");
    }

    function testCheckDebtAfterWithdrawWithTooHighDebt() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        uint256 expectedDebtTokenReduction =
            TokenMath.getVTokenBurnScaledAmount(expectedDebtReduction, WETH_VARIABLE_BORROW_INDEX);

        comparison.stateAfter.wethDebtTokenBalance = WETH_DEBT_TOKEN_BALANCE - expectedDebtTokenReduction + 1;

        bool result = comparison.checkDebtAfterWithdraw(sharesToRedeem);
        assertFalse(result, "Debt check should fail with debt higher than 2 wei tolerance");
    }

    function testCheckCollateralAfterWithdrawExactMatch() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);

        uint256 expectedLstATokenReduction =
            TokenMath.getATokenBurnScaledAmount(expectedCollateralReduction, LST_LIQUIDITY_INDEX);

        comparison.stateAfter.lstATokenBalance = LST_A_TOKEN_BALANCE - expectedLstATokenReduction;

        bool result = comparison.checkCollateralAfterWithdraw(sharesToRedeem);
        assertTrue(result, "Collateral check should pass with exact expected collateral amount");
    }

    function testCheckCollateralAfterWithdrawWithTooLowCollateral() public {
        uint256 sharesToRedeem = BASE_TOTAL_SUPPLY / 10;
        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);

        uint256 expectedLstATokenReduction =
            TokenMath.getATokenBurnScaledAmount(expectedCollateralReduction, LST_LIQUIDITY_INDEX);

        comparison.stateAfter.lstATokenBalance = LST_A_TOKEN_BALANCE - expectedLstATokenReduction - 1;

        bool result = comparison.checkCollateralAfterWithdraw(sharesToRedeem);
        assertFalse(result, "Collateral check should fail with collateral lower than 2 wei tolerance");
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

    function testFuzzCheckDebtAfterWithdraw(
        uint256 initialWethDebtTokenBalance,
        uint256 totalSupply,
        uint256 sharesToRedeem,
        uint256 wethVariableBorrowIndex
    ) public {
        initialWethDebtTokenBalance = bound(initialWethDebtTokenBalance, 1, type(uint128).max / 10);
        totalSupply = bound(totalSupply, 1, type(uint128).max / 10);
        sharesToRedeem = bound(sharesToRedeem, 1, totalSupply);
        wethVariableBorrowIndex = bound(wethVariableBorrowIndex, 1e27, 100e27);

        comparison.stateBefore.wethDebtTokenBalance = initialWethDebtTokenBalance;
        comparison.stateBefore.wethDebtAmount =
            TokenMath.getVTokenBalance(initialWethDebtTokenBalance, wethVariableBorrowIndex);
        comparison.stateBefore.vaultTotalSupply = totalSupply;

        uint256 expectedDebtReduction = comparison.stateBefore.proportionalDebtInEth(sharesToRedeem);
        uint256 expectedDebtTokenReduction =
            TokenMath.getVTokenBurnScaledAmount(expectedDebtReduction, wethVariableBorrowIndex);

        if (initialWethDebtTokenBalance <= expectedDebtTokenReduction) {
            comparison.stateAfter.wethDebtTokenBalance = 0;
        } else {
            comparison.stateAfter.wethDebtTokenBalance = initialWethDebtTokenBalance - expectedDebtTokenReduction;
        }

        comparison.stateAfter.wethVariableBorrowIndex = wethVariableBorrowIndex;

        assertTrue(comparison.checkDebtAfterWithdraw(sharesToRedeem));
    }

    function testFuzzCheckCollateralAfterWithdraw(
        uint256 initialLstATokenBalance,
        uint256 totalSupply,
        uint256 sharesToRedeem,
        uint256 lstLiquidityIndex
    ) public {
        initialLstATokenBalance = bound(initialLstATokenBalance, 1, type(uint128).max / 10);
        totalSupply = bound(totalSupply, 1, type(uint128).max / 10);
        sharesToRedeem = bound(sharesToRedeem, 1, totalSupply);
        lstLiquidityIndex = bound(lstLiquidityIndex, 1e27, 100e27);

        comparison.stateBefore.lstATokenBalance = initialLstATokenBalance;
        comparison.stateBefore.lstCollateralAmount =
            TokenMath.getATokenBalance(initialLstATokenBalance, lstLiquidityIndex);
        comparison.stateBefore.vaultTotalSupply = totalSupply;

        uint256 expectedCollateralReduction = comparison.stateBefore.proportionalCollateralInLst(sharesToRedeem);
        uint256 expectedLstATokenReduction =
            TokenMath.getATokenBurnScaledAmount(expectedCollateralReduction, lstLiquidityIndex);

        comparison.stateAfter.lstATokenBalance = initialLstATokenBalance - expectedLstATokenReduction;
        comparison.stateAfter.lstLiquidityIndex = lstLiquidityIndex;

        assertTrue(comparison.checkCollateralAfterWithdraw(sharesToRedeem));
    }

    function testHealthFactorMarginConstant() public view {
        assertEq(VaultSnapshotComparison.HEALTH_FACTOR_MARGIN, 0.000001e18);
    }

    function testEdgeCaseZeroShares() public {
        uint256 sharesToRedeem = 0;

        //comparison.stateAfter.wethDebtTokenBalance = comparison.stateAfter.wethDebtTokenBalance;

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
