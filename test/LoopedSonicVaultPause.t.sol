// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {console} from "forge-std/console.sol";

contract LoopedSonicVaultPauseTest is LoopedSonicVaultBase {
    function setUp() public override {
        super.setUp();
    }

    // =============================================================================
    // Individual Pause Function Tests
    // =============================================================================

    function testSetDepositsPaused() public {
        assertFalse(vault.depositsPaused(), "Deposits should not be paused initially");

        asAdmin();
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Deposits should be paused after setting");

        asAdmin();
        vault.setDepositsPaused(false);
        assertFalse(vault.depositsPaused(), "Deposits should be unpaused after setting");
    }

    function testSetWithdrawsPaused() public {
        assertFalse(vault.withdrawsPaused(), "Withdraws should not be paused initially");

        asAdmin();
        vault.setWithdrawsPaused(true);
        assertTrue(vault.withdrawsPaused(), "Withdraws should be paused after setting");

        asAdmin();
        vault.setWithdrawsPaused(false);
        assertFalse(vault.withdrawsPaused(), "Withdraws should be unpaused after setting");
    }

    function testSetDonationsPaused() public {
        assertFalse(vault.donationsPaused(), "Donations should not be paused initially");

        asAdmin();
        vault.setDonationsPaused(true);
        assertTrue(vault.donationsPaused(), "Donations should be paused after setting");

        asAdmin();
        vault.setDonationsPaused(false);
        assertFalse(vault.donationsPaused(), "Donations should be unpaused after setting");
    }

    function testSetUnwindsPaused() public {
        assertFalse(vault.unwindsPaused(), "Unwinds should not be paused initially");

        asAdmin();
        vault.setUnwindsPaused(true);
        assertTrue(vault.unwindsPaused(), "Unwinds should be paused after setting");

        asAdmin();
        vault.setUnwindsPaused(false);
        assertFalse(vault.unwindsPaused(), "Unwinds should be unpaused after setting");
    }

    // =============================================================================
    // Global Pause Function Tests
    // =============================================================================

    function testGlobalPause() public {
        assertFalse(vault.depositsPaused(), "Deposits should not be paused initially");
        assertFalse(vault.withdrawsPaused(), "Withdraws should not be paused initially");
        assertFalse(vault.donationsPaused(), "Donations should not be paused initially");
        assertFalse(vault.unwindsPaused(), "Unwinds should not be paused initially");

        asOperator();
        vault.pause();

        assertTrue(vault.depositsPaused(), "Deposits should be paused after global pause");
        assertTrue(vault.withdrawsPaused(), "Withdraws should be paused after global pause");
        assertTrue(vault.donationsPaused(), "Donations should be paused after global pause");
        assertTrue(vault.unwindsPaused(), "Unwinds should be paused after global pause");
    }

    // =============================================================================
    // Pause Access Control Tests
    // =============================================================================

    function testOnlyAdminCanSetDepositsPaused() public {
        vm.expectRevert();
        asUser(user1);
        vault.setDepositsPaused(true);

        vm.expectRevert();
        asOperator();
        vault.setDepositsPaused(true);

        asAdmin();
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Admin should be able to pause deposits");
    }

    function testOnlyAdminCanSetWithdrawsPaused() public {
        vm.expectRevert();
        asUser(user1);
        vault.setWithdrawsPaused(true);

        vm.expectRevert();
        asOperator();
        vault.setWithdrawsPaused(true);

        asAdmin();
        vault.setWithdrawsPaused(true);
        assertTrue(vault.withdrawsPaused(), "Admin should be able to pause withdraws");
    }

    function testOnlyAdminCanSetDonationsPaused() public {
        vm.expectRevert();
        asUser(user1);
        vault.setDonationsPaused(true);

        vm.expectRevert();
        asOperator();
        vault.setDonationsPaused(true);

        asAdmin();
        vault.setDonationsPaused(true);
        assertTrue(vault.donationsPaused(), "Admin should be able to pause donations");
    }

    function testOnlyAdminCanSetUnwindsPaused() public {
        vm.expectRevert();
        asUser(user1);
        vault.setUnwindsPaused(true);

        vm.expectRevert();
        asOperator();
        vault.setUnwindsPaused(true);

        asAdmin();
        vault.setUnwindsPaused(true);
        assertTrue(vault.unwindsPaused(), "Admin should be able to pause unwinds");
    }

    function testOnlyOperatorCanCallGlobalPause() public {
        vm.expectRevert();
        asUser(user1);
        vault.pause();

        vm.expectRevert();
        asAdmin();
        vault.pause();

        asOperator();
        vault.pause();
        assertTrue(vault.depositsPaused(), "Operator should be able to call global pause");
    }

    // =============================================================================
    // Pause Effects on Operations Tests
    // =============================================================================

    function testDepositPauseBlocksDeposits() public {
        asAdmin();
        vault.setDepositsPaused(true);

        bytes memory callbackData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether);

        vm.prank(user1);
        WETH.approve(address(vault), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("DepositsPaused()"));
        vault.deposit(user1, callbackData);
    }

    function testWithdrawPauseBlocksWithdraws() public {
        _setupStandardDeposit();

        asAdmin();
        vault.setWithdrawsPaused(true);

        bytes memory callbackData = abi.encodeWithSelector(this._withdrawCallback.selector, user1, 1, 0);

        vm.expectRevert(abi.encodeWithSignature("WithdrawsPaused()"));
        vault.withdraw(1, callbackData);
    }

    function testDonationPauseBlocksDonations() public {
        asAdmin();
        vault.setDonationsPaused(true);

        vm.startPrank(donator);
        WETH.approve(address(vault), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("DonationsPaused()"));
        vault.donate(1 ether, 0);
        vm.stopPrank();
    }

    function testUnwindPauseBlocksUnwinds() public {
        _setupStandardDeposit();

        asAdmin();
        vault.setUnwindsPaused(true);

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("UnwindsPaused()"));
        vault.unwind(1 ether, address(this), "");
        vm.stopPrank();
    }

    function testGlobalPauseBlocksAllOperations() public {
        _setupStandardDeposit();

        asOperator();
        vault.pause();

        bytes memory depositCallbackData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether);

        bytes memory withdrawCallbackData = abi.encodeWithSelector(this._withdrawCallback.selector, 0.1 ether);

        // Test deposit is blocked
        vm.startPrank(user2);
        WETH.approve(address(vault), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("DepositsPaused()"));
        vault.deposit(user2, depositCallbackData);
        vm.stopPrank();

        // Test withdraw is blocked
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("WithdrawsPaused()"));
        vault.withdraw(0.1 ether, withdrawCallbackData);
        vm.stopPrank();

        // Test donation is blocked
        vm.startPrank(donator);
        WETH.approve(address(vault), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("DonationsPaused()"));
        vault.donate(1 ether, 0);
        vm.stopPrank();

        // Test unwind is blocked
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("UnwindsPaused()"));
        vault.unwind(1 ether, address(this), "");
        vm.stopPrank();
    }

    // =============================================================================
    // Pause State Persistence Tests
    // =============================================================================

    function testPauseStateDoesNotChangeWhenSettingSameValue() public {
        // Initially false, setting to false should not emit event
        vm.recordLogs();
        asAdmin();
        vault.setDepositsPaused(false);
        assertEq(vm.getRecordedLogs().length, 0, "Should not emit event when setting same value");

        // Set to true
        asAdmin();
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Should be paused");

        // Setting to true again should not emit event
        vm.recordLogs();
        asAdmin();
        vault.setDepositsPaused(true);
        assertEq(vm.getRecordedLogs().length, 0, "Should not emit event when setting same value");
    }

    function testOperationsWorkAfterUnpause() public {
        // Pause all operations
        asOperator();
        vault.pause();

        // Unpause deposits only
        asAdmin();
        vault.setDepositsPaused(false);

        // Deposit should work
        uint256 shares = _depositToVault(user1, 1 ether, 0);
        assertTrue(shares > 0, "Should be able to deposit after unpause");

        // But withdraw should still be blocked
        uint256 sharesToRedeem = shares / 2;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);
        bytes memory callbackData =
            abi.encodeWithSelector(this._withdrawCallback.selector, user1, collateralInLst, debtInEth);

        vm.prank(user1);
        vault.transfer(address(this), sharesToRedeem);

        vm.expectRevert(abi.encodeWithSignature("WithdrawsPaused()"));
        vault.withdraw(sharesToRedeem, callbackData);

        // Unpause withdraws
        asAdmin();
        vault.setWithdrawsPaused(false);

        // Now withdraw should work
        _withdrawFromVault(user1, sharesToRedeem);
    }
}
