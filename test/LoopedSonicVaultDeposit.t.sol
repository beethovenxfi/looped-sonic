// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {VaultSnapshotComparison} from "../src/libraries/VaultSnapshotComparison.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultDepositTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    // Each call to vault.stakeWeth can result in the LST rounding in it's favor (1 wei)
    // In addition, aave will round down the collateral amount, so we account for that as well
    uint256 public constant NAV_DECREASE_TOLERANCE = MAX_LOOP_ITERATIONS + 1;

    function setUp() public override {
        super.setUp();

        vm.prank(user1);
        WETH.approve(address(this), type(uint256).max);
    }

    function testDepositSuccess() public {
        uint256 depositAmount = 1 ether;

        uint256 sharesBefore = vault.balanceOf(user1);
        VaultSnapshotComparison.Data memory data;
        data.stateBefore = vault.getVaultSnapshot();
        uint256 invariantBefore = vault.totalAssets() * 1e18 / vault.totalSupply();
        uint256 expectedShares = vault.convertToShares(depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        WETH.transferFrom(user1, address(this), depositAmount);

        vm.expectEmit(true, true, false, false);
        emit ILoopedSonicVault.Deposit(address(this), user1, 0, 0, 0);

        vault.deposit(user1, depositData);

        data.stateAfter = vault.getVaultSnapshot();
        uint256 sharesAfter = vault.balanceOf(user1);
        uint256 invariantAfter = vault.totalAssets() * 1e18 / vault.totalSupply();

        assertApproxEqAbs(
            data.navIncreaseEth(), depositAmount, NAV_DECREASE_TOLERANCE, "NAV should increase by the deposit amount"
        );

        assertEq(invariantAfter, invariantBefore, "Invariant should not change");
        assertApproxEqAbs(
            vault.totalSupply(),
            data.stateBefore.vaultTotalSupply + expectedShares,
            NAV_DECREASE_TOLERANCE,
            "Total supply should increase by expected amount"
        );

        assertApproxEqAbs(
            sharesAfter,
            sharesBefore + expectedShares,
            NAV_DECREASE_TOLERANCE,
            "User's shares should increase by expected amount"
        );
    }

    function testDepositRevertsWhenPaused() public {
        vm.prank(admin);
        vault.setDepositsPaused(true);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.DepositsPaused.selector));
        vault.deposit(user1, depositData);
    }

    function testDepositRevertsWhenNotInitialized() public {
        LoopedSonicVault uninitializedVault = _getUninitializedVault();

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotInitialized.selector));
        uninitializedVault.deposit(user1, depositData);
    }

    function testDepositRevertsWithZeroReceiver() public {
        uint256 depositAmount = 1 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAddress.selector));
        vault.deposit(address(0), depositData);
    }

    function testDepositRevertsWithHealthFactorAboveTarget() public {
        uint256 depositAmount = 1 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._invalidDeposit.selector, depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.HealthFactorNotInRange.selector));
        vault.deposit(user1, depositData);
    }

    function testDepositRevertsWithHealthFactorBelowTarget() public {
        uint256 depositAmount = 1 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory belowTargetHealthFactorData =
            abi.encodeWithSelector(this._belowTargetHealthFactorCallback.selector);
        bytes memory depositData =
            abi.encodeWithSelector(this._depositCallback.selector, depositAmount, belowTargetHealthFactorData);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.HealthFactorNotInRange.selector));
        vault.deposit(user1, depositData);
    }

    function _belowTargetHealthFactorCallback() external {
        uint256 lstAmount = 0.1e18;

        vault.aaveWithdrawLst(lstAmount);
        vault.sendLst(address(this), lstAmount);
    }

    function testDepositRevertsWithNavIncreaseBelowMin() public {
        uint256 depositAmount = 0.01 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._emptyDepositCallback.selector);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NavIncreaseBelowMin.selector));
        vault.deposit(user1, depositData);
    }

    function _emptyDepositCallback() external {
        // do nothing
    }

    function testDepositSuccessWithNavIncreaseAboveMin() public {
        uint256 depositAmount = 0.010001 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        vault.deposit(user1, depositData);
    }

    function testDepositWithDifferentReceiver() public {
        uint256 depositAmount = 1 ether;
        address receiver = user2;

        WETH.transferFrom(user1, address(this), depositAmount);

        uint256 sharesBeforeReceiver = vault.balanceOf(receiver);
        uint256 sharesBeforeUser = vault.balanceOf(user1);
        uint256 expectedShares = vault.convertToShares(depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        vault.deposit(receiver, depositData);

        uint256 sharesAfterReceiver = vault.balanceOf(receiver);
        uint256 sharesAfterUser = vault.balanceOf(user1);

        assertEq(sharesAfterUser, sharesBeforeUser, "User should not receive shares");
        assertApproxEqAbs(
            sharesAfterReceiver,
            sharesBeforeReceiver + expectedShares,
            NAV_DECREASE_TOLERANCE,
            "Receiver should receive shares"
        );
    }

    function testDepositRevertsWithReadOnlyReentrancy() public {
        uint256 depositAmount = 1 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory readonlyReentrancyData = abi.encodeWithSelector(this._attemptReadOnlyReentrancy.selector);
        bytes memory depositData =
            abi.encodeWithSelector(this._depositCallback.selector, depositAmount, readonlyReentrancyData);

        vault.deposit(user1, depositData);
    }

    function testDepositRevertsWithReentrancy() public {
        uint256 depositAmount = 1 ether;

        WETH.transferFrom(user1, address(this), depositAmount);

        bytes memory reentrancyData = abi.encodeWithSelector(this._attemptReentrancy.selector);
        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, reentrancyData);

        vault.deposit(user1, depositData);
    }

    function testDepositRevertsWithNonZeroSessionBalances() public {
        uint256 depositAmount = 1 ether;

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory testData = abi.encodeWithSelector(this._createLstSessionBalance.selector);
        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, testData);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.LstSessionBalanceNotZero.selector));
        vault.deposit(user1, depositData);

        bytes memory testData2 = abi.encodeWithSelector(this._createWethSessionBalance.selector);
        bytes memory depositData2 = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, testData2);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.WethSessionBalanceNotZero.selector));
        vault.deposit(user1, depositData2);
    }

    function _createLstSessionBalance() external {
        vault.aaveWithdrawLst(1);
    }

    function _createWethSessionBalance() external {
        vault.aaveBorrowWeth(1);
    }

    function testDepositAfterTargetHealthFactorChange() public {
        _setupStandardDeposit();

        uint256 startingTargetHealthFactor = vault.targetHealthFactor();
        uint256 newTargetHealthFactor = 1.6e18;

        uint256 depositAmount = 100 ether;

        vm.prank(admin);
        vault.setTargetHealthFactor(newTargetHealthFactor);

        assertEq(vault.targetHealthFactor(), newTargetHealthFactor, "Target health factor should be changed");

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        assertEq(
            vault.getHealthFactor(), startingTargetHealthFactor, "Health factor should be at old target before deposit"
        );

        vault.deposit(user1, depositData);

        assertEq(vault.getHealthFactor(), newTargetHealthFactor, "Health factor should be at new target after deposit");
    }

    function testLargeDepositBelowTargetHealthFactor() public {
        uint256 targetHealthFactor = vault.targetHealthFactor();
        _setupStandardDeposit();

        uint256 depositAmount = 100 ether;

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        assertEq(vault.getHealthFactor(), targetHealthFactor, "Health factor should be at target after setup");

        vm.warp(block.timestamp + 10 * 365 days);

        assertLt(vault.getHealthFactor(), targetHealthFactor, "Health factor should be below target after warp");

        vault.deposit(user1, depositData);

        assertEq(
            vault.getHealthFactor(), targetHealthFactor, "Health factor should be back at target after large deposit"
        );
    }

    function testSmallDepositBelowTargetHealthFactor() public {
        uint256 targetHealthFactor = vault.targetHealthFactor();
        _setupStandardDeposit();

        uint256 depositAmount = 0.02 ether;

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        assertEq(vault.getHealthFactor(), targetHealthFactor, "Health factor should be at target after setup");

        // advance 10 years
        vm.warp(block.timestamp + 10 * 365 days);

        uint256 healthFactorAfterWarp = vault.getHealthFactor();

        assertLt(healthFactorAfterWarp, targetHealthFactor, "Health factor should be below target after warp");

        vault.deposit(user1, depositData);

        assertGt(vault.getHealthFactor(), healthFactorAfterWarp, "Health factor should be above previous after deposit");

        // A small deposit relative to the vault size will not be enough to bring the health factor back up to the target
        assertLt(
            vault.getHealthFactor(), targetHealthFactor, "Health factor should be below target after small deposit"
        );
    }

    function testLargeDepositAboveTargetHealthFactor() public {
        _setupStandardDeposit();

        uint256 donateAmount = 1_000 ether;
        uint256 depositAmount = 100 ether;
        uint256 targetHealthFactor = vault.targetHealthFactor();

        _donateAaveLstATokensToVault(user1, donateAmount);

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        assertGt(vault.getHealthFactor(), targetHealthFactor, "Health factor should be above target after donation");

        vault.deposit(user1, depositData);

        assertEq(
            vault.getHealthFactor(), targetHealthFactor, "Health factor should be back at target after large deposit"
        );
    }

    function testDepositSharesIssuedAtNewRateAfterDonation() public {
        _setupStandardDeposit();

        uint256 depositAmount = 100 ether;

        _dealWethToAddress(address(this), depositAmount * 2);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        uint256 sharesBefore = vault.deposit(user1, depositData);

        // Before the donation, shares should be issued at 1:1 to the deposit amount, as the rate is 1
        assertApproxEqAbs(
            sharesBefore, depositAmount, NAV_DECREASE_TOLERANCE, "Shares should be equal to deposit amount"
        );

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 donateAmount = vault.convertToShares(snapshotBefore.netAssetValueInEth());

        _dealWethToAddress(address(this), snapshotBefore.netAssetValueInEth());

        _donateAaveLstATokensToVault(user1, donateAmount);

        uint256 sharesAfter = vault.deposit(user1, depositData);

        // we've now doubled the value of each share, so depositing the same amount should result in half as many shares issued
        assertApproxEqAbs(
            sharesAfter, sharesBefore / 2, NAV_DECREASE_TOLERANCE, "Shares should be half of the previous amount"
        );
    }

    function testSmallDepositAboveTargetHealthFactor() public {
        _setupStandardDeposit();

        uint256 donateAmount = 1_000 ether;
        uint256 depositAmount = 0.1 ether;
        uint256 targetHealthFactor = vault.targetHealthFactor();

        _donateAaveLstATokensToVault(user1, donateAmount);

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        assertGt(vault.getHealthFactor(), targetHealthFactor, "Health factor should be above target after donation");

        vault.deposit(user1, depositData);

        assertEq(
            vault.getHealthFactor(), targetHealthFactor, "Health factor should be back at target after small deposit"
        );
    }

    function testFuzzDepositSuccess(uint256 depositAmount) public {
        // TODO: figure out how to up the aave deposit limit
        vm.assume(depositAmount >= 0.02 ether && depositAmount <= 5_000_000 ether);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        WETH.deposit{value: depositAmount}();

        uint256 sharesBefore = vault.balanceOf(user1);
        VaultSnapshotComparison.Data memory data;
        data.stateBefore = vault.getVaultSnapshot();
        uint256 invariantBefore = vault.totalAssets() * 1e18 / vault.totalSupply();
        uint256 expectedShares = vault.convertToShares(depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        WETH.transferFrom(user1, address(this), depositAmount);

        vm.expectEmit(true, true, false, false);
        emit ILoopedSonicVault.Deposit(address(this), user1, 0, 0, 0);

        vault.deposit(user1, depositData);

        data.stateAfter = vault.getVaultSnapshot();
        uint256 sharesAfter = vault.balanceOf(user1);
        uint256 invariantAfter = vault.totalAssets() * 1e18 / vault.totalSupply();

        assertApproxEqAbs(
            data.navIncreaseEth(), depositAmount, NAV_DECREASE_TOLERANCE, "NAV should increase by the deposit amount"
        );

        assertEq(invariantAfter, invariantBefore, "Invariant should not change");
        assertApproxEqAbs(
            vault.totalSupply(),
            data.stateBefore.vaultTotalSupply + expectedShares,
            NAV_DECREASE_TOLERANCE,
            "Total supply should increase by expected amount"
        );

        assertApproxEqAbs(
            sharesAfter,
            sharesBefore + expectedShares,
            NAV_DECREASE_TOLERANCE,
            "User's shares should increase by expected amount"
        );
    }

    function testFuzzDepositComplex(uint256 depositAmount, uint256 donateAmount, uint256 warpTime) public {
        depositAmount = bound(depositAmount, 0.02 ether, 10_000_000 ether);
        donateAmount = bound(donateAmount, 0.02 ether, 5_000_000 ether);
        warpTime = bound(warpTime, 0, 10 * 365 days);

        _setupStandardDeposit();

        uint256 targetHealthFactor = vault.targetHealthFactor();

        _donateAaveLstATokensToVault(user1, donateAmount);

        vm.deal(user1, depositAmount);

        vm.prank(user1);
        WETH.deposit{value: depositAmount}();

        vm.prank(user1);
        WETH.transfer(address(this), depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        vm.warp(block.timestamp + warpTime);

        uint256 healthFactorAfterWarp = vault.getHealthFactor();

        uint256 invariantBefore = vault.totalAssets() * 1e18 / vault.totalSupply();
        uint256 rateBefore = vault.getRate();

        vault.deposit(user1, depositData);

        uint256 invariantAfter = vault.totalAssets() * 1e18 / vault.totalSupply();
        uint256 rateAfter = vault.getRate();

        assertApproxEqAbs(rateAfter, rateBefore, 1e5, "Rate should not change");
        assertApproxEqAbs(invariantAfter, invariantBefore, 1e5, "Invariant should not change");

        // Rounding should always be in the correct direction
        assertGe(rateAfter, rateBefore, "Rate should never decrease");
        assertGe(invariantAfter, invariantBefore, "Invariant should never decrease");

        if (healthFactorAfterWarp > targetHealthFactor) {
            assertEq(vault.getHealthFactor(), targetHealthFactor, "Health factor should be at target after deposit");
        } else {
            assertGe(
                vault.getHealthFactor(), healthFactorAfterWarp, "Health factor should be above previous after deposit"
            );
        }
    }

    function _invalidDeposit(uint256 amount) external {
        // We do a single loop, which will leave the health factor higher than the target
        // causing a revert
        vault.pullWeth(amount);
        uint256 lstAmount = vault.stakeWeth(amount);

        vault.aaveSupplyLst(lstAmount);
    }
}
