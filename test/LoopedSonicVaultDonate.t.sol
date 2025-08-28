// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultDonateTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;

    function testDonateWethSuccess() public {
        _setupStandardDeposit();

        uint256 donateAmount = 0.1 ether;

        vm.startPrank(donator);
        WETH.approve(address(vault), donateAmount);

        uint256 wethBalanceBefore = WETH.balanceOf(donator);
        uint256 lastDonationTimeBefore = vault.lastDonationTime();

        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        vm.expectEmit(true, false, false, false);
        emit ILoopedSonicVault.Donate(donator, donateAmount, donateAmount, 0);

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        vault.donate(donateAmount, 0);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(WETH.balanceOf(donator), wethBalanceBefore - donateAmount, "Donator WETH balance should decrease");
        assertEq(WETH.balanceOf(address(vault)), 0, "Vault should not hold WETH after donate");
        assertApproxEqAbs(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth + donateAmount,
            1,
            "LST collateral should increase by the donated amount"
        );
        assertEq(vault.lastDonationTime(), block.timestamp, "Last donation time should be updated");
        assertEq(snapshotAfter.vaultTotalSupply, snapshotBefore.vaultTotalSupply, "Total supply should not change");
        assertEq(snapshotAfter.wethDebtAmount, snapshotBefore.wethDebtAmount, "WETH debt should not change");

        vm.stopPrank();
    }

    function testDonateLstSuccess() public {
        _setupStandardDeposit();

        uint256 donateAmount = 0.1 ether;

        vm.prank(donator);
        WETH.withdraw(donateAmount);
        vm.prank(donator);
        uint256 lstAmount = LST.deposit{value: donateAmount}();

        vm.startPrank(donator);
        LST.approve(address(vault), lstAmount);

        uint256 lstBalanceBefore = LST.balanceOf(donator);

        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        vm.expectEmit(true, false, false, false);
        emit ILoopedSonicVault.Donate(donator, donateAmount, donateAmount, 0);

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        vault.donate(0, lstAmount);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(LST.balanceOf(donator), lstBalanceBefore - lstAmount, "Donator LST balance should decrease");
        assertEq(LST.balanceOf(address(vault)), 0, "Vault should not hold LST after donate");
        assertApproxEqAbs(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth + donateAmount,
            1,
            "LST collateral should increase by the donated amount"
        );
        assertEq(snapshotAfter.wethDebtAmount, snapshotBefore.wethDebtAmount, "WETH debt should not change");
        assertEq(snapshotAfter.vaultTotalSupply, snapshotBefore.vaultTotalSupply, "Total supply should not change");
        assertEq(vault.lastDonationTime(), block.timestamp, "Last donation time should be updated");

        vm.stopPrank();
    }

    function testDonateBothWethAndLstSuccess() public {
        _setupStandardDeposit();

        uint256 wethDonateAmount = 0.05 ether;
        uint256 lstDonateAmount = 0.05 ether;

        // Get some LST for the donator
        vm.prank(donator);
        WETH.withdraw(lstDonateAmount);
        vm.prank(donator);
        uint256 lstAmount = LST.deposit{value: lstDonateAmount}();

        vm.startPrank(donator);
        WETH.approve(address(vault), wethDonateAmount);
        LST.approve(address(vault), lstAmount);

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 totalExpectedDonationEth = wethDonateAmount + LST.convertToAssets(lstAmount);

        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        vm.expectEmit(true, false, false, false);
        emit ILoopedSonicVault.Donate(donator, 0, 0, 0);

        vault.donate(wethDonateAmount, lstAmount);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(vault.lastDonationTime(), block.timestamp, "Last donation time should be updated");

        assertApproxEqAbs(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth + totalExpectedDonationEth,
            1,
            "LST collateral should increase by the donated amount"
        );

        vm.stopPrank();
    }

    function testDonateRevertsWhenPaused() public {
        vm.prank(admin);
        vault.setDonationsPaused(true);

        vm.startPrank(donator);
        WETH.approve(address(vault), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.DonationsPaused.selector));
        vault.donate(1 ether, 0);

        vm.stopPrank();
    }

    function testDonateRevertsWithZeroAmount() public {
        vm.prank(donator);
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.donate(0, 0);
    }

    function testDonateRevertsWithoutDonatorRole() public {
        vm.startPrank(user1);
        WETH.approve(address(vault), 1 ether);

        vm.expectRevert();
        vault.donate(1 ether, 0);

        vm.stopPrank();
    }

    function testDonateRevertsBeforeCooldownPeriod() public {
        uint256 donateAmount = 0.01 ether;

        vm.startPrank(donator);
        WETH.approve(address(vault), donateAmount * 2);

        // First donation should work (after initial cooldown from initialization)
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);
        vault.donate(donateAmount, 0);

        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() / 2);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.DonationCooldownNotPassed.selector));
        vault.donate(donateAmount, 0);

        vm.stopPrank();
    }

    function testDonateRevertsWhenAmountTooHigh() public {
        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 maxDonationEth = snapshot.netAssetValueInEth() * vault.DONATION_MAX_PERCENT() / 1e18;
        uint256 excessiveAmount = maxDonationEth + 1 ether;

        vm.startPrank(donator);
        WETH.approve(address(vault), excessiveAmount);

        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.DonationAmountTooHigh.selector));
        vault.donate(excessiveAmount, 0);

        vm.stopPrank();
    }

    function testDonateRevertsWithoutApproval() public {
        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        vm.prank(donator);
        vm.expectRevert();
        vault.donate(0.01 ether, 0);
    }

    function testDonateWithinMaxPercentage() public {
        _setupStandardDeposit();

        // Move forward past the donation cooldown
        vm.warp(block.timestamp + vault.DONATION_COOLDOWN() + 1);

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 maxDonationEth = snapshot.netAssetValueInEth() * vault.DONATION_MAX_PERCENT() / 1e18;

        vm.startPrank(donator);
        WETH.approve(address(vault), maxDonationEth);

        // Should succeed with max allowed amount
        vault.donate(maxDonationEth, 0);

        vm.stopPrank();
    }
}
