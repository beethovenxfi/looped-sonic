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

        vm.prank(admin);
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Deposits should be paused after setting");

        vm.prank(admin);
        vault.setDepositsPaused(false);
        assertFalse(vault.depositsPaused(), "Deposits should be unpaused after setting");
    }

    function testSetWithdrawsPaused() public {
        assertFalse(vault.withdrawsPaused(), "Withdraws should not be paused initially");

        vm.prank(admin);
        vault.setWithdrawsPaused(true);
        assertTrue(vault.withdrawsPaused(), "Withdraws should be paused after setting");

        vm.prank(admin);
        vault.setWithdrawsPaused(false);
        assertFalse(vault.withdrawsPaused(), "Withdraws should be unpaused after setting");
    }

    function testSetUnwindsPaused() public {
        assertFalse(vault.unwindsPaused(), "Unwinds should not be paused initially");

        vm.prank(admin);
        vault.setUnwindsPaused(true);
        assertTrue(vault.unwindsPaused(), "Unwinds should be paused after setting");

        vm.prank(admin);
        vault.setUnwindsPaused(false);
        assertFalse(vault.unwindsPaused(), "Unwinds should be unpaused after setting");
    }

    // =============================================================================
    // Global Pause Function Tests
    // =============================================================================

    function testGlobalPause() public {
        assertFalse(vault.depositsPaused(), "Deposits should not be paused initially");
        assertFalse(vault.withdrawsPaused(), "Withdraws should not be paused initially");
        assertFalse(vault.unwindsPaused(), "Unwinds should not be paused initially");

        vm.prank(operator);
        vault.pause();

        assertTrue(vault.depositsPaused(), "Deposits should be paused after global pause");
        assertTrue(vault.withdrawsPaused(), "Withdraws should be paused after global pause");
        assertTrue(vault.unwindsPaused(), "Unwinds should be paused after global pause");
    }

    // =============================================================================
    // Pause Access Control Tests
    // =============================================================================

    function testOnlyAdminCanSetDepositsPaused() public {
        vm.expectRevert();
        vm.prank(user1);
        vault.setDepositsPaused(true);

        vm.expectRevert();
        vm.prank(operator);
        vault.setDepositsPaused(true);

        vm.prank(admin);
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Admin should be able to pause deposits");
    }

    function testOnlyAdminCanSetWithdrawsPaused() public {
        vm.expectRevert();
        vm.prank(user1);
        vault.setWithdrawsPaused(true);

        vm.expectRevert();
        vm.prank(operator);
        vault.setWithdrawsPaused(true);

        vm.prank(admin);
        vault.setWithdrawsPaused(true);
        assertTrue(vault.withdrawsPaused(), "Admin should be able to pause withdraws");
    }

    function testOnlyAdminCanSetUnwindsPaused() public {
        vm.expectRevert();
        vm.prank(user1);
        vault.setUnwindsPaused(true);

        vm.expectRevert();
        vm.prank(operator);
        vault.setUnwindsPaused(true);

        vm.prank(admin);
        vault.setUnwindsPaused(true);
        assertTrue(vault.unwindsPaused(), "Admin should be able to pause unwinds");
    }

    function testOnlyOperatorCanCallGlobalPause() public {
        vm.expectRevert();
        vm.prank(user1);
        vault.pause();

        vm.expectRevert();
        vm.prank(admin);
        vault.pause();

        vm.prank(operator);
        vault.pause();
        assertTrue(vault.depositsPaused(), "Operator should be able to call global pause");
    }

    // =============================================================================
    // Pause Effects on Operations Tests
    // =============================================================================

    function testDepositPauseBlocksDeposits() public {
        vm.prank(admin);
        vault.setDepositsPaused(true);

        bytes memory callbackData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether, "");

        vm.prank(user1);
        WETH.approve(address(vault), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("DepositsPaused()"));
        vault.deposit(user1, callbackData);
    }

    function testWithdrawPauseBlocksWithdraws() public {
        _setupStandardDeposit();

        vm.prank(admin);
        vault.setWithdrawsPaused(true);

        bytes memory callbackData = abi.encodeWithSelector(this._withdrawCallback.selector, user1, 1, 0);

        vm.expectRevert(abi.encodeWithSignature("WithdrawsPaused()"));
        vault.withdraw(1, callbackData);
    }

    function testUnwindPauseBlocksUnwinds() public {
        _setupStandardDeposit();

        vm.prank(admin);
        vault.setUnwindsPaused(true);

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("UnwindsPaused()"));
        vault.unwind(1 ether, address(this), "");
        vm.stopPrank();
    }

    function testGlobalPauseBlocksAllOperations() public {
        _setupStandardDeposit();

        vm.prank(operator);
        vault.pause();

        bytes memory depositCallbackData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether, "");

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
        vm.prank(admin);
        vault.setDepositsPaused(false);
        assertEq(vm.getRecordedLogs().length, 0, "Should not emit event when setting same value");

        // Set to true
        vm.prank(admin);
        vault.setDepositsPaused(true);
        assertTrue(vault.depositsPaused(), "Should be paused");

        // Setting to true again should not emit event
        vm.recordLogs();
        vm.prank(admin);
        vault.setDepositsPaused(true);
        assertEq(vm.getRecordedLogs().length, 0, "Should not emit event when setting same value");
    }

    function testOperationsWorkAfterUnpause() public {
        // Pause all operations
        vm.prank(operator);
        vault.pause();

        // Unpause deposits only
        vm.prank(admin);
        vault.setDepositsPaused(false);

        // Deposit should work
        uint256 shares = _depositToVault(user1, 1 ether, 0, "");
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
        vm.prank(admin);
        vault.setWithdrawsPaused(false);

        // Now withdraw should work
        _withdrawFromVault(user1, sharesToRedeem, "");
    }
}
