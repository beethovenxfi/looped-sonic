// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultAdminTest is LoopedSonicVaultBase {
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

        vm.expectRevert(abi.encodeWithSignature("UnwindsPaused()"));
        vault.unwind(1 ether, "");
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
        vm.expectRevert(abi.encodeWithSignature("UnwindsPaused()"));
        vault.unwind(1 ether, "");
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

    function testSetTargetHealthFactor() public {
        uint256 newHealthFactor = 1.5e18;

        assertNotEq(newHealthFactor, vault.targetHealthFactor(), "New target health factor should be different");

        vm.prank(admin);
        vault.setTargetHealthFactor(newHealthFactor);

        assertEq(vault.targetHealthFactor(), newHealthFactor, "Target health factor should be updated");
    }

    function testSetTargetHealthFactorMinimumValidation() public {
        uint256 belowMinimum = vault.MIN_TARGET_HEALTH_FACTOR() - 0.1e18;

        vm.expectRevert(abi.encodeWithSignature("TargetHealthFactorTooLow()"));
        vm.prank(admin);
        vault.setTargetHealthFactor(belowMinimum);
    }

    function testSetTargetHealthFactorAtMinimum() public {
        uint256 minimumHealthFactor = vault.MIN_TARGET_HEALTH_FACTOR();

        vm.prank(admin);
        vault.setTargetHealthFactor(minimumHealthFactor);

        assertEq(vault.targetHealthFactor(), minimumHealthFactor, "Should accept minimum health factor");
    }

    function testOnlyAdminCanSetTargetHealthFactor() public {
        uint256 newHealthFactor = 1.5e18;

        vm.expectRevert();
        vm.prank(user1);
        vault.setTargetHealthFactor(newHealthFactor);

        vm.expectRevert();
        vm.prank(operator);
        vault.setTargetHealthFactor(newHealthFactor);

        vm.prank(admin);
        vault.setTargetHealthFactor(newHealthFactor);
        assertEq(vault.targetHealthFactor(), newHealthFactor, "Admin should be able to set target health factor");
    }

    function testSetAllowedUnwindSlippagePercent() public {
        uint256 newSlippage = 0.01e18; // 1%

        assertNotEq(
            newSlippage, vault.allowedUnwindSlippagePercent(), "New allowed unwind slippage percent should be different"
        );

        vm.prank(admin);
        vault.setAllowedUnwindSlippagePercent(newSlippage);

        assertEq(vault.allowedUnwindSlippagePercent(), newSlippage, "Allowed unwind slippage percent should be updated");
    }

    function testSetAllowedUnwindSlippagePercentMaximumValidation() public {
        uint256 aboveMaximum = vault.MAX_UNWIND_SLIPPAGE_PERCENT() + 0.01e18;

        vm.expectRevert(abi.encodeWithSignature("AllowedUnwindSlippageTooHigh()"));
        vm.prank(admin);
        vault.setAllowedUnwindSlippagePercent(aboveMaximum);
    }

    function testSetAllowedUnwindSlippagePercentAtMaximum() public {
        uint256 maximumSlippage = vault.MAX_UNWIND_SLIPPAGE_PERCENT();

        vm.prank(admin);
        vault.setAllowedUnwindSlippagePercent(maximumSlippage);

        assertEq(vault.allowedUnwindSlippagePercent(), maximumSlippage, "Should accept maximum slippage");
    }

    function testSetAllowedUnwindSlippagePercentZero() public {
        uint256 zeroSlippage = 0;

        vm.prank(admin);
        vault.setAllowedUnwindSlippagePercent(zeroSlippage);

        assertEq(vault.allowedUnwindSlippagePercent(), zeroSlippage, "Should accept zero slippage");
    }

    function testOnlyAdminCanSetAllowedUnwindSlippagePercent() public {
        uint256 newSlippage = 0.01e18;

        vm.expectRevert();
        vm.prank(user1);
        vault.setAllowedUnwindSlippagePercent(newSlippage);

        vm.expectRevert();
        vm.prank(operator);
        vault.setAllowedUnwindSlippagePercent(newSlippage);

        vm.prank(admin);
        vault.setAllowedUnwindSlippagePercent(newSlippage);
        assertEq(
            vault.allowedUnwindSlippagePercent(),
            newSlippage,
            "Admin should be able to set allowed unwind slippage percent"
        );
    }

    // =============================================================================
    // Aave Capo Rate Provider Tests
    // =============================================================================

    function testSetAaveCapoRateProvider() public {
        address newProvider = address(0x123456789);
        address initialProvider = address(vault.aaveCapoRateProvider());

        assertNotEq(newProvider, initialProvider, "New provider should be different from initial");

        vm.prank(admin);
        vault.setAaveCapoRateProvider(newProvider);

        assertEq(address(vault.aaveCapoRateProvider()), newProvider, "Aave capo rate provider should be updated");
    }

    function testOnlyAdminCanSetAaveCapoRateProvider() public {
        address newProvider = address(0x123456789);

        vm.expectRevert();
        vm.prank(user1);
        vault.setAaveCapoRateProvider(newProvider);

        vm.expectRevert();
        vm.prank(operator);
        vault.setAaveCapoRateProvider(newProvider);

        vm.prank(admin);
        vault.setAaveCapoRateProvider(newProvider);
        assertEq(
            address(vault.aaveCapoRateProvider()), newProvider, "Admin should be able to set aave capo rate provider"
        );
    }

    function testSetAaveCapoRateProviderToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAddress.selector));
        vault.setAaveCapoRateProvider(address(0));
    }

    function testOnlyAdminCanSetProtocolFeePercent() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setProtocolFeePercent(0.01e18);
        vm.stopPrank();
    }

    function testOnlyAdminCanSetTreasuryAddress() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setTreasuryAddress(user2);
        vm.stopPrank();
    }

    function testProtocolFeePercentTooHigh() public {
        uint256 maxProtocolFeePercent = vault.MAX_PROTOCOL_FEE_PERCENT();
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ProtocolFeePercentTooHigh.selector));
        vault.setProtocolFeePercent(maxProtocolFeePercent + 0.01e18);
        vm.stopPrank();
    }

    function testTreasuryAddressCannotBeZero() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAddress.selector));
        vault.setTreasuryAddress(address(0));
        vm.stopPrank();
    }
}
