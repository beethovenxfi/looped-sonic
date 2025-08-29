// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract LoopedSonicVaultUnwindTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;

    function setUp() public override {
        super.setUp();

        // Fund the test contract with WETH for liquidation simulation
        vm.deal(address(this), 1000 ether);
        WETH.deposit{value: 1000 ether}();

        vm.prank(operator);
        WETH.approve(address(vault), type(uint256).max);
    }

    function testUnwindSuccess() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshotBefore.lstCollateralAmount / 10;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, lstAmountToWithdraw);
        uint256 expectedWethAmount = LST.convertToAssets(lstAmountToWithdraw);

        vm.expectEmit(true, true, true, false);
        emit ILoopedSonicVault.Unwind(operator, lstAmountToWithdraw, expectedWethAmount);

        vm.prank(operator);
        vault.unwind(lstAmountToWithdraw, address(this), liquidationData);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(
            snapshotAfter.lstCollateralAmount,
            snapshotBefore.lstCollateralAmount - lstAmountToWithdraw,
            "LST collateral should decrease by withdrawn amount"
        );

        assertApproxEqAbs(
            snapshotAfter.wethDebtAmount,
            snapshotBefore.wethDebtAmount - expectedWethAmount,
            1,
            "WETH debt should decrease by repaid amount"
        );

        assertApproxEqAbs(
            snapshotAfter.netAssetValueInEth(),
            snapshotBefore.netAssetValueInEth(),
            1,
            "Net asset value should not change when liquidating at the redemption rate"
        );

        assertTrue(snapshotAfter.healthFactor() > snapshotBefore.healthFactor(), "Health factor should increase");
        assertTrue(
            snapshotAfter.availableBorrowsInEth() > snapshotBefore.availableBorrowsInEth(),
            "Available borrows should increase"
        );
    }

    function testUnwindRevertsWithoutOperatorRole() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshot.lstCollateralAmount / 10;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, lstAmountToWithdraw);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, vault.OPERATOR_ROLE()
            )
        );
        vm.prank(user1);
        vault.unwind(lstAmountToWithdraw, address(this), liquidationData);
    }

    function testUnwindRevertsWhenNotInitialized() public {
        // Create a new vault that's not initialized
        LoopedSonicVault uninitializedVault =
            new LoopedSonicVault(address(WETH), address(LST), AAVE_POOL, E_MODE_CATEGORY_ID, admin);

        vm.startPrank(admin);
        uninitializedVault.grantRole(uninitializedVault.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        bytes memory liquidationData = abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotInitialized.selector));
        vm.prank(operator);
        uninitializedVault.unwind(1 ether, address(this), liquidationData);
    }

    function testUnwindRevertsWithZeroAmount() public {
        _setupStandardDeposit();

        bytes memory liquidationData = abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, 0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.UnwindAmountBelowMin.selector));
        vm.prank(operator);
        vault.unwind(0, address(this), liquidationData);
    }

    function testUnwindRevertsWithExcessiveAmount() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 excessiveAmount = snapshot.lstCollateralAmount + 1 ether;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, excessiveAmount);

        vm.expectRevert();
        vm.prank(operator);
        vault.unwind(excessiveAmount, address(this), liquidationData);
    }

    function testUnwindWithMaxAmount() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 collateralMin = snapshotBefore.wethDebtAmount * 1e18 / snapshotBefore.liquidationThresholdScaled18();
        uint256 maxWithdrawable = snapshotBefore.lstCollateralAmountInEth - collateralMin;
        // Aave's base currency is in 8 decimals
        uint256 maxWithdrawableInLst = LST.convertToShares(maxWithdrawable) * 0.9999999e18 / 1e18;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstAtRedemptionRate.selector, maxWithdrawableInLst);

        vm.prank(operator);
        vault.unwind(maxWithdrawableInLst, address(this), liquidationData);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(snapshotAfter.netAssetValueInEth(), snapshotBefore.netAssetValueInEth());
    }

    function testUnwindWithSlippage() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshotBefore.lstCollateralAmount / 10; // Unwind 10%
        uint256 allowedSlippagePercent = vault.allowedUnwindSlippagePercent() / 2;
        uint256 slippageAmount = LST.convertToAssets(lstAmountToWithdraw) * allowedSlippagePercent / 1e18;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstWithSlippage.selector, lstAmountToWithdraw, slippageAmount);

        uint256 expectedWethAmount = LST.convertToAssets(lstAmountToWithdraw) - slippageAmount;

        vm.expectEmit(true, true, true, false);
        emit ILoopedSonicVault.Unwind(operator, lstAmountToWithdraw, expectedWethAmount);

        vm.prank(operator);
        vault.unwind(lstAmountToWithdraw, address(this), liquidationData);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(
            snapshotAfter.lstCollateralAmount,
            snapshotBefore.lstCollateralAmount - lstAmountToWithdraw,
            "LST collateral should decrease by withdrawn amount"
        );

        assertApproxEqAbs(
            snapshotAfter.wethDebtAmount,
            snapshotBefore.wethDebtAmount - expectedWethAmount,
            1,
            "WETH debt should decrease by repaid amount with high slippage"
        );

        assertEq(
            snapshotAfter.netAssetValueInEth(),
            snapshotBefore.netAssetValueInEth() - slippageAmount,
            "Net asset value should decrease by slippage amount"
        );

        assertTrue(snapshotAfter.healthFactor() > snapshotBefore.healthFactor(), "Health factor should increase");
        assertTrue(
            snapshotAfter.availableBorrowsInEth() > snapshotBefore.availableBorrowsInEth(),
            "Available borrows should increase"
        );
    }

    function testUnwindWithMaxSlippage() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshotBefore.lstCollateralAmount / 10; // Unwind 10%
        uint256 slippagePercent = vault.allowedUnwindSlippagePercent();
        uint256 slippageAmount = LST.convertToAssets(lstAmountToWithdraw) * slippagePercent / 1e18;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstWithSlippage.selector, lstAmountToWithdraw, slippageAmount);

        vm.prank(operator);
        vault.unwind(lstAmountToWithdraw, address(this), liquidationData);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(snapshotAfter.netAssetValueInEth(), snapshotBefore.netAssetValueInEth() - slippageAmount);
    }

    function testUnwindWithOneWeiSlippage() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshotBefore.lstCollateralAmount / 10; // Unwind 10%

        bytes memory liquidationData =
            abi.encodeWithSelector(this._liquidateLstWithSlippage.selector, lstAmountToWithdraw, 1);

        vm.prank(operator);
        vault.unwind(lstAmountToWithdraw, address(this), liquidationData);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(snapshotAfter.netAssetValueInEth(), snapshotBefore.netAssetValueInEth() - 1);
    }

    function testUnwindRevertsWithInvalidContract() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshot.lstCollateralAmount / 4;

        // Try to call a non-existent function
        bytes memory invalidData = abi.encodeWithSelector(bytes4(0x12345678), lstAmountToWithdraw);

        vm.prank(operator);
        vm.expectRevert();
        vault.unwind(lstAmountToWithdraw, address(this), invalidData);
    }

    function _liquidateLstAtRedemptionRate(uint256 lstAmount) external returns (uint256 wethAmount) {
        // We simulate liqudation at the redemption rate
        wethAmount = LST.convertToAssets(lstAmount);

        // burn the LST
        LST.transfer(address(1), lstAmount);

        // transfer the WETH to the operator
        WETH.transfer(address(operator), wethAmount);

        return wethAmount;
    }

    function _liquidateLstWithSlippage(uint256 lstAmount, uint256 slippageAmount)
        external
        returns (uint256 wethAmount)
    {
        wethAmount = LST.convertToAssets(lstAmount) - slippageAmount;

        // burn the LST
        LST.transfer(address(1), lstAmount);

        // transfer the WETH to the operator
        WETH.transfer(address(operator), wethAmount);

        return wethAmount;
    }
}
