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
import "forge-std/Vm.sol";

contract LoopedSonicVaultWithdrawTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    uint256 public constant NAV_DECREASE_TOLERANCE = MAX_LOOP_ITERATIONS + 1;

    function setUp() public override {
        super.setUp();
    }

    function testWithdrawSuccess() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 2;

        uint256 sharesBefore = vault.balanceOf(user1);
        VaultSnapshotComparison.Data memory data;
        data.stateBefore = vault.getVaultSnapshot();

        (uint256 expectedCollateralInLst, uint256 expectedDebtInEth) =
            vault.getCollateralAndDebtForShares(sharesToRedeem);

        _withdrawFromVault(user1, sharesToRedeem, "");

        data.stateAfter = vault.getVaultSnapshot();
        uint256 sharesAfter = vault.balanceOf(user1);

        assertEq(sharesAfter, sharesBefore - sharesToRedeem, "Shares should be burned");

        assertApproxEqAbs(
            data.navDecreaseEth(),
            vault.convertToAssets(sharesToRedeem),
            NAV_DECREASE_TOLERANCE,
            "NAV should decrease proportionally"
        );
    }

    function testWithdrawRevertsWhenPaused() public {
        uint256 shares = _setupStandardDeposit();

        vm.prank(admin);
        vault.setWithdrawsPaused(true);

        bytes memory withdrawData = abi.encodeWithSelector(this._withdrawCallback.selector, user1, 1 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.WithdrawsPaused.selector));
        vault.withdraw(shares / 2, withdrawData);
    }

    function testWithdrawRevertsWhenNotInitialized() public {
        LoopedSonicVault uninitializedVault = _getUninitializedVault();

        bytes memory withdrawData = abi.encodeWithSelector(this._withdrawCallback.selector, user1, 1 ether, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotInitialized.selector));
        uninitializedVault.withdraw(1 ether, withdrawData);
    }

    function testWithdrawRevertsWithNotEnoughShares() public {
        _setupStandardDeposit();
        uint256 minShares = vault.MIN_SHARES_TO_REDEEM() - 1;

        bytes memory withdrawData = abi.encodeWithSelector(this._withdrawCallback.selector, user1, 1 ether, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotEnoughShares.selector));
        vault.withdraw(minShares, withdrawData);
    }

    function testWithdrawRevertsWithInvalidDebtAfterWithdraw() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        bytes memory invalidWithdrawData = abi.encodeWithSelector(
            this._invalidWithdrawCallback.selector, user1, sharesToRedeem, collateralInLst, debtInEth
        );

        vm.prank(user1);
        vault.transfer(address(this), sharesToRedeem);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InvalidDebtAfterWithdraw.selector));
        vault.withdraw(sharesToRedeem, invalidWithdrawData);
    }

    function testWithdrawRevertsWithInvalidCollateralAfterWithdraw() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        bytes memory invalidCollateralWithdrawData = abi.encodeWithSelector(
            this._invalidCollateralWithdrawCallback.selector, user1, sharesToRedeem, collateralInLst, debtInEth
        );

        vm.prank(user1);
        vault.transfer(address(this), sharesToRedeem);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InvalidCollateralAfterWithdraw.selector));
        vault.withdraw(sharesToRedeem, invalidCollateralWithdrawData);
    }

    function testWithdrawBurnsSharesUpfront() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;

        // _withdrawFromVault will transfer the shares to this contract, so add them to the balance
        uint256 sharesBefore = vault.balanceOf(address(this)) + sharesToRedeem;

        bytes memory callbackData =
            abi.encodeWithSelector(this._checkSharesWereBurned.selector, sharesBefore, sharesToRedeem);

        _withdrawFromVault(user1, sharesToRedeem, callbackData);
    }

    function _checkSharesWereBurned(uint256 sharesBefore, uint256 sharesToRedeem) public {
        uint256 sharesAfter = vault.balanceOf(address(this));
        assertEq(sharesAfter, sharesBefore - sharesToRedeem, "Shares should have been burned before the callback");
    }

    function testWithdrawRevertsWithReentrancy() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;

        bytes memory reentrancyData = abi.encodeWithSelector(this._attemptReentrancy.selector);

        _withdrawFromVault(user1, sharesToRedeem, reentrancyData);
    }

    function testWithdrawRevertsWithReadOnlyReentrancy() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;

        bytes memory readonlyReentrancyData = abi.encodeWithSelector(this._attemptReadOnlyReentrancy.selector);

        _withdrawFromVault(user1, sharesToRedeem, readonlyReentrancyData);
    }

    function testWithdrawRevertsWithNonZeroSessionBalances() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        vm.prank(user1);
        vault.transfer(address(this), sharesToRedeem);

        bytes memory testData = abi.encodeWithSelector(this._createLstSessionBalance.selector);
        bytes memory withdrawData =
            abi.encodeWithSelector(this._withdrawCallback.selector, user1, collateralInLst, debtInEth, testData);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.LstSessionBalanceNotZero.selector));
        vault.withdraw(sharesToRedeem, withdrawData);

        vm.prank(user1);
        vault.transfer(address(this), sharesToRedeem);

        (collateralInLst, debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        bytes memory testData2 = abi.encodeWithSelector(this._createWethSessionBalance.selector);
        bytes memory withdrawData2 =
            abi.encodeWithSelector(this._withdrawCallback.selector, user1, collateralInLst, debtInEth, testData2);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.WethSessionBalanceNotZero.selector));
        vault.withdraw(sharesToRedeem, withdrawData2);
    }

    function testWithdrawableCollateralIncreasesAfterDonation() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;
        uint256 donateAmount = 100 ether;

        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);
        uint256 expectedCollateralIncrease = LST.convertToShares(donateAmount) * sharesToRedeem / vault.totalSupply();

        _donateAaveLstATokensToVault(user1, donateAmount);

        (uint256 collateralInLstAfter, uint256 debtInEthAfter) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        assertEq(debtInEthAfter, debtInEth, "Debt should not change");
        assertApproxEqAbs(
            collateralInLstAfter,
            collateralInLst + expectedCollateralIncrease,
            2,
            "Collateral should increase relative to the donate amount"
        );
    }

    function testWithdrawDebtIncreasesAsTimePasses() public {
        uint256 shares = _setupStandardDeposit();
        uint256 sharesToRedeem = shares / 10;
        uint256 donateAmount = 100 ether;

        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        vm.warp(block.timestamp + 10 days);

        (uint256 collateralInLstAfter, uint256 debtInEthAfter) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        assertEq(collateralInLst, collateralInLstAfter, "Collateral should not change");
        assertGt(debtInEthAfter, debtInEth, "Debt should increase");
    }

    function testWithdrawSuccessFuzz(uint256 depositAmount, uint256 sharesToRedeem) public {
        _setupStandardDeposit();

        depositAmount = bound(depositAmount, 0.02 ether, 10_000_000 ether);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        WETH.deposit{value: depositAmount}();

        _depositToVault(user1, depositAmount, 0, "");

        // We cap the upper bound to what is burnt on initialization
        sharesToRedeem = bound(sharesToRedeem, vault.MIN_SHARES_TO_REDEEM(), vault.totalSupply() - vault.INIT_AMOUNT());

        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(user1);
        VaultSnapshotComparison.Data memory data;
        data.stateBefore = vault.getVaultSnapshot();
        uint256 nav = data.stateBefore.netAssetValueInEth();
        uint256 expectedNav = nav - (nav * sharesToRedeem / vault.totalSupply());

        (uint256 expectedCollateralInLst, uint256 expectedDebtInEth) =
            vault.getCollateralAndDebtForShares(sharesToRedeem);

        _withdrawFromVault(user1, sharesToRedeem, "");

        data.stateAfter = vault.getVaultSnapshot();
        uint256 sharesAfter = vault.balanceOf(user1);

        assertEq(sharesAfter, sharesBefore - sharesToRedeem, "Shares should be burned");

        assertApproxEqAbs(data.stateAfter.netAssetValueInEth(), expectedNav, 6, "NAV should decrease proportionally");
    }

    function _invalidWithdrawCallback(address user, uint256 sharesToRedeem, uint256 collateralInLst, uint256 debtInEth)
        external
    {
        // Only repay half the debt
        uint256 partialDebtRepayment = debtInEth / 2;

        vm.deal(address(this), partialDebtRepayment);
        WETH.deposit{value: partialDebtRepayment}();

        vault.pullWeth(partialDebtRepayment);
        vault.aaveRepayWeth(partialDebtRepayment);

        // Still withdraw all collateral (this will cause invalid debt state)
        vault.aaveWithdrawLst(collateralInLst);
        vault.sendLst(address(1), collateralInLst);
    }

    function _invalidCollateralWithdrawCallback(
        address user,
        uint256 sharesToRedeem,
        uint256 collateralInLst,
        uint256 debtInEth
    ) external {
        vm.deal(address(this), debtInEth);
        WETH.deposit{value: debtInEth}();

        vault.pullWeth(debtInEth);
        vault.aaveRepayWeth(debtInEth);

        // Only withdraw half the collateral (this will cause invalid collateral state)
        uint256 partialCollateralWithdraw = collateralInLst / 2;
        vault.aaveWithdrawLst(partialCollateralWithdraw);
        vault.sendLst(address(1), partialCollateralWithdraw);
    }

    function _createLstSessionBalance() external {
        vm.deal(address(this), 1 ether);

        uint256 lstAmount = vault.LST().deposit{value: 1 ether}();
        vault.pullLst(lstAmount);
    }

    function _createWethSessionBalance() external {
        vm.deal(address(this), 1 ether);

        WETH.deposit{value: 1 ether}();

        vault.pullWeth(1 ether);
    }
}
