// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract VaultSnapshotTest is Test {
    using VaultSnapshot for VaultSnapshot.Data;

    VaultSnapshot.Data private snapshot;

    function setUp() public {
        snapshot = VaultSnapshot.Data({
            lstCollateralAmount: 100e18,
            lstCollateralAmountInEth: 100e18,
            wethDebtAmount: 50e18,
            liquidationThreshold: 8500,
            ltv: 8000,
            vaultTotalSupply: 1000e18
        });
    }

    function testNetAssetValueInEth() public view {
        uint256 expected = snapshot.lstCollateralAmountInEth - snapshot.wethDebtAmount;
        uint256 nav = snapshot.netAssetValueInEth();
        assertEq(nav, expected);
    }

    function testNetAssetValueInEthWithZeroDebt() public {
        snapshot.wethDebtAmount = 0;
        uint256 nav = snapshot.netAssetValueInEth();

        assertEq(nav, snapshot.lstCollateralAmountInEth, "Net asset value should be equal to collateral in ETH");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testNetAssetValueInEthWithHigherDebt() public {
        snapshot.wethDebtAmount = snapshot.lstCollateralAmountInEth + 20e18;

        // This should revert because the debt is higher than the collateral
        vm.expectRevert();
        snapshot.netAssetValueInEth();
    }

    function testProportionalCollateralInLst() public view {
        uint256 shares = snapshot.vaultTotalSupply / 10; // 10% of total shares
        uint256 expected = snapshot.lstCollateralAmount * shares / snapshot.vaultTotalSupply;
        uint256 collateral = snapshot.proportionalCollateralInLst(shares);
        assertEq(collateral, expected);
    }

    function testProportionalCollateralInLstWithMaxShares() public view {
        uint256 shares = snapshot.vaultTotalSupply;
        uint256 expected = snapshot.lstCollateralAmount;
        uint256 collateral = snapshot.proportionalCollateralInLst(shares);
        assertEq(collateral, expected);
    }

    function testProportionalCollateralInLstRoundsDown() public {
        snapshot.lstCollateralAmount = 100e18;
        snapshot.vaultTotalSupply = 3;
        uint256 shares = 1;
        uint256 expected = snapshot.lstCollateralAmount * shares / snapshot.vaultTotalSupply;
        uint256 collateral = snapshot.proportionalCollateralInLst(shares);
        assertEq(collateral, expected);

        // Verify it rounds down by checking the remainder would have been lost
        uint256 remainder = snapshot.lstCollateralAmount % snapshot.vaultTotalSupply;
        assertGt(remainder, 0, "Should have remainder to demonstrate rounding down");
    }

    function testProportionalDebtInEth() public view {
        uint256 shares = snapshot.vaultTotalSupply / 10; // 10% of total shares
        uint256 expected = Math.mulDiv(snapshot.wethDebtAmount, shares, snapshot.vaultTotalSupply, Math.Rounding.Ceil);
        uint256 debt = snapshot.proportionalDebtInEth(shares);
        assertEq(debt, expected);
    }

    function testProportionalDebtInEthWithMaxShares() public view {
        uint256 shares = snapshot.vaultTotalSupply;
        uint256 expected = snapshot.wethDebtAmount;
        uint256 debt = snapshot.proportionalDebtInEth(shares);
        assertEq(debt, expected);
    }

    function testProportionalDebtInEthRoundsUp() public {
        snapshot.wethDebtAmount = 100e18;
        snapshot.vaultTotalSupply = 3;
        uint256 shares = 1;
        uint256 expected = Math.mulDiv(snapshot.wethDebtAmount, shares, snapshot.vaultTotalSupply, Math.Rounding.Ceil);
        uint256 debt = snapshot.proportionalDebtInEth(shares);
        assertEq(debt, expected);

        // Verify it rounds up by comparing to floor division
        uint256 floorResult = snapshot.wethDebtAmount * shares / snapshot.vaultTotalSupply;
        uint256 remainder = (snapshot.wethDebtAmount * shares) % snapshot.vaultTotalSupply;
        if (remainder > 0) {
            assertGt(debt, floorResult, "Should round up when there's a remainder");
        }
    }

    function testAvailableBorrowsInEth() public view {
        uint256 maxBorrow = snapshot.lstCollateralAmountInEth * snapshot.ltv / 10_000;
        uint256 expected = maxBorrow - snapshot.wethDebtAmount;
        uint256 availableBorrows = snapshot.availableBorrowsInEth();
        assertEq(availableBorrows, expected);
    }

    function testAvailableBorrowsInEthWithZeroCollateral() public {
        snapshot.lstCollateralAmountInEth = 0;
        uint256 availableBorrows = snapshot.availableBorrowsInEth();
        assertEq(availableBorrows, 0);
    }

    function testAvailableBorrowsInEthWithMaxDebt() public {
        uint256 maxBorrow = snapshot.lstCollateralAmountInEth * snapshot.ltv / 10_000;
        snapshot.wethDebtAmount = maxBorrow;
        uint256 availableBorrows = snapshot.availableBorrowsInEth();
        assertEq(availableBorrows, 0);
    }

    function testAvailableBorrowsInEthWithExcessiveDebt() public {
        uint256 maxBorrow = snapshot.lstCollateralAmountInEth * snapshot.ltv / 10_000;
        snapshot.wethDebtAmount = maxBorrow + 10e18;

        uint256 availableBorrows = snapshot.availableBorrowsInEth();

        assertEq(availableBorrows, 0);
    }

    function testLiquidationThresholdScaled18() public view {
        uint256 expected = snapshot.liquidationThreshold * 1e14;
        uint256 scaledThreshold = snapshot.liquidationThresholdScaled18();
        assertEq(scaledThreshold, expected);
    }

    function testHealthFactor() public view {
        uint256 expected =
            snapshot.lstCollateralAmountInEth * snapshot.liquidationThresholdScaled18() / snapshot.wethDebtAmount;
        uint256 hf = snapshot.healthFactor();
        assertEq(hf, expected);
    }

    function testHealthFactorWithZeroDebt() public {
        snapshot.wethDebtAmount = 0;
        uint256 hf = snapshot.healthFactor();
        assertEq(hf, type(uint256).max);
    }

    function testHealthFactorAtLiquidationThreshold() public {
        // Set debt such that health factor = 1
        uint256 debtForHF1 = snapshot.lstCollateralAmountInEth * snapshot.liquidationThresholdScaled18() / 1e18;
        snapshot.wethDebtAmount = debtForHF1;
        uint256 hf = snapshot.healthFactor();
        assertEq(hf, 1e18);
    }

    function testHealthFactorBelowOne() public {
        // Set debt higher than liquidation threshold allows
        uint256 debtForHF1 = snapshot.lstCollateralAmountInEth * snapshot.liquidationThresholdScaled18() / 1e18;
        snapshot.wethDebtAmount = debtForHF1 + 10e18;
        uint256 expected =
            snapshot.lstCollateralAmountInEth * snapshot.liquidationThresholdScaled18() / snapshot.wethDebtAmount;
        uint256 hf = snapshot.healthFactor();
        assertLt(hf, 1e18);
        assertEq(hf, expected);
    }

    function testFuzzProportionalCollateralInLst(uint256 lstAmount, uint256 shares, uint256 totalSupply) public {
        lstAmount = bound(lstAmount, 0, type(uint128).max);
        totalSupply = bound(totalSupply, 1, type(uint128).max);
        shares = bound(shares, 0, totalSupply);

        VaultSnapshot.Data memory data = VaultSnapshot.Data({
            lstCollateralAmount: lstAmount,
            lstCollateralAmountInEth: 0,
            wethDebtAmount: 0,
            liquidationThreshold: 8500,
            ltv: 8000,
            vaultTotalSupply: totalSupply
        });

        uint256 result = data.proportionalCollateralInLst(shares);
        assertLe(result, lstAmount);

        if (shares == totalSupply) {
            assertEq(result, lstAmount);
        }
    }

    function testFuzzProportionalDebtInEth(uint256 debtAmount, uint256 shares, uint256 totalSupply) public {
        debtAmount = bound(debtAmount, 0, type(uint128).max);
        totalSupply = bound(totalSupply, 1, type(uint128).max);
        shares = bound(shares, 0, totalSupply);

        VaultSnapshot.Data memory data = VaultSnapshot.Data({
            lstCollateralAmount: 0,
            lstCollateralAmountInEth: 0,
            wethDebtAmount: debtAmount,
            liquidationThreshold: 8500,
            ltv: 8000,
            vaultTotalSupply: totalSupply
        });

        uint256 result = data.proportionalDebtInEth(shares);
        assertGe(result, debtAmount * shares / totalSupply);

        if (shares == totalSupply) {
            assertEq(result, debtAmount);
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testFuzzAvailableBorrowsInEth(uint256 collateralInEth, uint256 debtAmount, uint16 ltv) public {
        ltv = uint16(bound(ltv, 0, 10000));
        collateralInEth = bound(collateralInEth, 0, type(uint128).max);
        debtAmount = bound(debtAmount, 0, type(uint128).max);

        VaultSnapshot.Data memory data = VaultSnapshot.Data({
            lstCollateralAmount: 0,
            lstCollateralAmountInEth: collateralInEth,
            wethDebtAmount: debtAmount,
            liquidationThreshold: 8500,
            ltv: ltv,
            vaultTotalSupply: 1
        });

        uint256 result;

        if (collateralInEth == 0) {
            result = data.availableBorrowsInEth();
            assertEq(result, 0);
        } else if (collateralInEth * ltv / 10000 < debtAmount) {
            result = data.availableBorrowsInEth();

            assertEq(result, 0);
        } else {
            result = data.availableBorrowsInEth();
            uint256 maxBorrow = collateralInEth * ltv / 10000;
            if (debtAmount >= maxBorrow) {
                assertEq(result, 0);
            } else {
                assertEq(result, maxBorrow - debtAmount);
            }
        }
    }

    function testFuzzHealthFactor(uint256 collateralInEth, uint256 debtAmount, uint16 liquidationThreshold) public {
        collateralInEth = bound(collateralInEth, 0, type(uint128).max);
        debtAmount = bound(debtAmount, 1, type(uint128).max);
        liquidationThreshold = uint16(bound(liquidationThreshold, 1, 10000));

        VaultSnapshot.Data memory data = VaultSnapshot.Data({
            lstCollateralAmount: 0,
            lstCollateralAmountInEth: collateralInEth,
            wethDebtAmount: debtAmount,
            liquidationThreshold: liquidationThreshold,
            ltv: 8000,
            vaultTotalSupply: 1
        });

        uint256 result = data.healthFactor();
        uint256 expected = collateralInEth * liquidationThreshold * 1e14 / debtAmount;
        assertEq(result, expected);
    }

    function testEdgeCaseZeroValues() public {
        VaultSnapshot.Data memory zeroData = VaultSnapshot.Data({
            lstCollateralAmount: 0,
            lstCollateralAmountInEth: 0,
            wethDebtAmount: 0,
            liquidationThreshold: 0,
            ltv: 0,
            vaultTotalSupply: 1
        });

        assertEq(zeroData.netAssetValueInEth(), 0);
        assertEq(zeroData.proportionalCollateralInLst(100), 0);
        assertEq(zeroData.proportionalDebtInEth(100), 0);
        assertEq(zeroData.availableBorrowsInEth(), 0);
        assertEq(zeroData.liquidationThresholdScaled18(), 0);
        assertEq(zeroData.healthFactor(), type(uint256).max);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testEdgeCaseMaxValues() public {
        VaultSnapshot.Data memory maxData = VaultSnapshot.Data({
            lstCollateralAmount: type(uint256).max,
            lstCollateralAmountInEth: type(uint256).max,
            wethDebtAmount: 1,
            liquidationThreshold: 10000,
            ltv: 10000,
            vaultTotalSupply: type(uint256).max
        });

        assertEq(maxData.proportionalCollateralInLst(1), 1);
        assertEq(maxData.proportionalDebtInEth(1), 1);

        vm.expectRevert();
        maxData.healthFactor();
    }
}
