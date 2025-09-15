// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultPrimitivesTest is LoopedSonicVaultBase {
    function testPullWeth() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testPullWethCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testPullWethCallback() external {
        uint256 wethAmount = 5 ether;

        vm.deal(address(this), wethAmount);
        WETH.deposit{value: wethAmount}();

        uint256 wethBalanceBefore = WETH.balanceOf(address(this));

        vault.pullWeth(wethAmount);

        uint256 wethBalanceAfter = WETH.balanceOf(address(this));
        (uint256 wethSessionBalance, uint256 lstSessionBalance) = vault.getSessionBalances();

        assertEq(wethBalanceAfter, wethBalanceBefore - wethAmount, "WETH balance should decrease by pulled amount");
        assertEq(wethSessionBalance, wethAmount, "WETH session balance should be the pulled amount");
        assertEq(lstSessionBalance, 0, "LST session balance should be 0");

        // We need to zero out the session balance to avoid the tx failing
        vault.sendWeth(address(this), wethAmount);
    }

    function testStakeWeth() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testStakeWethCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testStakeWethCallback() external {
        uint256 wethAmount = 5 ether;

        vm.deal(address(this), wethAmount);
        WETH.deposit{value: wethAmount}();

        uint256 lstBalanceBefore = vault.LST().balanceOf(address(this));

        vault.pullWeth(wethAmount);
        uint256 lstAmount = vault.stakeWeth(wethAmount);

        (uint256 wethSessionBalance, uint256 lstSessionBalance) = vault.getSessionBalances();

        assertEq(wethSessionBalance, 0, "WETH balance should have been used to mint LST");
        assertEq(lstSessionBalance, lstAmount, "LST session balance should be minted amount");

        vault.sendLst(address(this), lstAmount);

        (uint256 wethSessionBalanceAfter, uint256 lstSessionBalanceAfter) = vault.getSessionBalances();
        uint256 lstBalanceAfter = vault.LST().balanceOf(address(this));

        assertEq(lstBalanceAfter, lstBalanceBefore + lstAmount, "LST balance should increase by minted amount");
        assertEq(wethSessionBalanceAfter, 0, "WETH session balance should be 0");
        assertEq(lstSessionBalanceAfter, 0, "LST session balance should be 0");
    }

    function testSendWeth() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testSendWethCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testSendWethCallback() external {
        uint256 wethAmount = 3 ether;

        vm.deal(address(this), wethAmount);
        WETH.deposit{value: wethAmount}();

        vault.pullWeth(wethAmount);

        uint256 recipientBalanceBefore = WETH.balanceOf(user1);
        (uint256 wethSessionBalanceBefore,) = vault.getSessionBalances();

        assertEq(wethSessionBalanceBefore, wethAmount, "WETH session balance should be the pulled amount");

        vault.sendWeth(user1, wethAmount);

        uint256 recipientBalanceAfter = WETH.balanceOf(user1);
        (uint256 wethSessionBalanceAfter,) = vault.getSessionBalances();

        assertEq(recipientBalanceAfter, recipientBalanceBefore + wethAmount, "Recipient should receive WETH");
        assertEq(wethSessionBalanceAfter, 0, "WETH session balance should be 0");
    }

    function testSendLst() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testSendLstCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testSendLstCallback() external {
        uint256 wethAmount = 3 ether;

        vm.deal(address(this), wethAmount);
        WETH.deposit{value: wethAmount}();

        vault.pullWeth(wethAmount);
        uint256 lstAmount = vault.stakeWeth(wethAmount);

        uint256 recipientBalanceBefore = vault.LST().balanceOf(user1);
        (, uint256 lstSessionBalanceBefore) = vault.getSessionBalances();

        assertEq(lstSessionBalanceBefore, lstAmount, "LST session balance should be the staked amount");

        vault.sendLst(user1, lstAmount);

        uint256 recipientBalanceAfter = vault.LST().balanceOf(user1);
        (, uint256 lstSessionBalanceAfter) = vault.getSessionBalances();

        assertEq(recipientBalanceAfter, recipientBalanceBefore + lstAmount, "Recipient should receive LST");
        assertEq(lstSessionBalanceAfter, 0, "LST session balance should be 0");
    }

    function testPullLst() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testPullLstCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testPullLstCallback() external {
        uint256 ethAmount = 3 ether;

        vm.deal(address(this), ethAmount);
        uint256 lstAmount = vault.LST().deposit{value: ethAmount}();

        uint256 lstBalanceBefore = vault.LST().balanceOf(address(this));
        (, uint256 lstSessionBalanceBefore) = vault.getSessionBalances();

        vault.pullLst(lstAmount);

        uint256 lstBalanceAfter = vault.LST().balanceOf(address(this));
        (, uint256 lstSessionBalanceAfter) = vault.getSessionBalances();

        assertEq(lstBalanceAfter, lstBalanceBefore - lstAmount, "LST balance should decrease by pulled amount");
        assertEq(lstSessionBalanceAfter, lstSessionBalanceBefore + lstAmount, "LST session balance should increase");

        vault.sendLst(address(this), lstAmount);
    }

    function testAaveSupplyLst() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testAaveSupplyLstCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveSupplyLstCallback() external {
        uint256 ethAmount = 3 ether;

        vm.deal(address(this), ethAmount);
        uint256 lstAmount = vault.LST().deposit{value: ethAmount}();

        uint256 aaveLstBalanceBefore = vault.getAaveLstCollateralAmount();

        vault.pullLst(lstAmount);

        (, uint256 lstSessionBalanceBefore) = vault.getSessionBalances();

        assertEq(lstSessionBalanceBefore, lstAmount, "LST session balance should be the pulled amount");

        vault.aaveSupplyLst(lstAmount);

        (, uint256 lstSessionBalanceAfter) = vault.getSessionBalances();

        assertEq(lstSessionBalanceAfter, 0, "LST session balance should be 0");

        uint256 aaveLstBalanceAfter = vault.getAaveLstCollateralAmount();

        assertApproxEqAbs(
            aaveLstBalanceAfter,
            aaveLstBalanceBefore + lstAmount,
            1,
            "Aave LST balance should increase by the lst amount"
        );

        vault.aaveWithdrawLst(lstAmount);
        vault.sendLst(address(this), lstAmount);
    }

    function testAaveWithdrawLst() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testAaveWithdrawLstCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveWithdrawLstCallback() external {
        uint256 ethAmount = 3 ether;

        vm.deal(address(this), ethAmount);
        uint256 lstAmount = vault.LST().deposit{value: ethAmount}();

        vault.pullLst(lstAmount);
        vault.aaveSupplyLst(lstAmount);

        uint256 aaveLstBalanceBefore = vault.getAaveLstCollateralAmount();

        vault.aaveWithdrawLst(lstAmount);

        uint256 aaveLstBalanceAfter = vault.getAaveLstCollateralAmount();

        assertApproxEqAbs(
            aaveLstBalanceAfter,
            aaveLstBalanceBefore - lstAmount,
            1,
            "Aave LST balance should decrease by the lst amount"
        );

        vault.sendLst(address(this), lstAmount);
    }

    function testAaveBorrowWeth() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testAaveBorrowWethCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveBorrowWethCallback() external {
        uint256 borrowAmount = 1 ether;

        uint256 aaveWethDebtBalanceBefore = vault.getAaveWethDebtAmount();

        vault.aaveBorrowWeth(borrowAmount);

        uint256 aaveWethDebtBalanceAfter = vault.getAaveWethDebtAmount();

        assertApproxEqAbs(
            aaveWethDebtBalanceAfter,
            aaveWethDebtBalanceBefore + borrowAmount,
            1,
            "Aave WETH debt balance should increase"
        );

        vault.aaveRepayWeth(borrowAmount);
    }

    function testFuzzFullyRepayWeth(uint256 depositAmount) public {
        vm.assume(depositAmount >= 0.02 ether && depositAmount <= 5_000_000 ether);
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        WETH.deposit{value: depositAmount}();

        _depositToVault(user1, depositAmount, 0, "");

        bytes memory callbackData = abi.encodeWithSelector(this._testAaveFullyRepayWethCallback.selector);
        _depositToVault(user1, 1 ether, 0, callbackData);
    }

    function _testAaveFullyRepayWethCallback() external {
        uint256 aaveDebtAmount = vault.getAaveWethDebtAmount();

        vm.deal(address(this), aaveDebtAmount);
        WETH.deposit{value: aaveDebtAmount}();

        uint256 wethBalanceBefore = WETH.balanceOf(address(this));

        vault.pullWeth(aaveDebtAmount);
        vault.aaveRepayWeth(aaveDebtAmount);

        uint256 wethBalanceAfter = WETH.balanceOf(address(this));

        assertEq(
            wethBalanceAfter, wethBalanceBefore - aaveDebtAmount, "WETH balance should decrease by the repaid amount"
        );

        uint256 aaveWethDebtBalanceAfter = vault.getAaveWethDebtAmount();

        assertEq(aaveWethDebtBalanceAfter, 0, "Aave WETH debt balance should be 0");

        // zero the session balances, account for rounding
        vault.aaveBorrowWeth(aaveDebtAmount - 1);
        vault.sendWeth(address(this), aaveDebtAmount - 1);
        uint256 aaveWethDebtBalanceFinal = vault.getAaveWethDebtAmount();
        assertEq(aaveWethDebtBalanceFinal, aaveDebtAmount, "Aave WETH debt balance should be back to original");
    }

    function testAaveRepayWeth() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testAaveRepayWethCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveRepayWethCallback() external {
        uint256 borrowAmount = 1 ether;

        vault.aaveBorrowWeth(borrowAmount);

        uint256 aaveWethDebtBalanceBefore = vault.getAaveWethDebtAmount();

        vault.aaveRepayWeth(borrowAmount);

        uint256 aaveWethDebtBalanceAfter = vault.getAaveWethDebtAmount();

        assertApproxEqAbs(
            aaveWethDebtBalanceAfter,
            aaveWethDebtBalanceBefore - borrowAmount,
            2,
            "Aave WETH debt balance should decrease"
        );
    }

    function testAaveRepayWethRevertsWhenInsufficientSessionBalance() public {
        _setupStandardDeposit();

        bytes memory callbackData =
            abi.encodeWithSelector(this._testAaveRepayWethRevertsWhenInsufficientSessionBalanceCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveRepayWethRevertsWhenInsufficientSessionBalanceCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InsufficientWethSessionBalance.selector));
        vault.aaveRepayWeth(10 ether);
    }

    function testSendWethRevertsWhenInsufficientSessionBalance() public {
        _setupStandardDeposit();

        bytes memory callbackData =
            abi.encodeWithSelector(this._testSendWethRevertsWhenInsufficientSessionBalanceCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testSendWethRevertsWhenInsufficientSessionBalanceCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InsufficientWethSessionBalance.selector));
        vault.sendWeth(user1, 10 ether);
    }

    function testSendLstRevertsWhenInsufficientSessionBalance() public {
        _setupStandardDeposit();

        bytes memory callbackData =
            abi.encodeWithSelector(this._testSendLstRevertsWhenInsufficientSessionBalanceCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testSendLstRevertsWhenInsufficientSessionBalanceCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InsufficientLstSessionBalance.selector));
        vault.sendLst(user1, 10 ether);
    }

    function testAaveSupplyLstRevertsWhenInsufficientSessionBalance() public {
        _setupStandardDeposit();

        bytes memory callbackData =
            abi.encodeWithSelector(this._testAaveSupplyLstRevertsWhenInsufficientSessionBalanceCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testAaveSupplyLstRevertsWhenInsufficientSessionBalanceCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.InsufficientLstSessionBalance.selector));
        vault.aaveSupplyLst(10 ether);
    }

    function testNotAllowedWhenLocked() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testNotAllowedWhenLockedCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testNotAllowedWhenLockedCallback() external {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.pullWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.sendWeth(user1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.sendLst(user1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.pullLst(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.aaveBorrowWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.aaveRepayWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.aaveSupplyLst(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotAllowed.selector));
        vault.aaveWithdrawLst(1 ether);

        vm.stopPrank();
    }

    function testRevertsWhenNotLocked() public {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.pullWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.sendWeth(user1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.sendLst(user1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.pullLst(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.aaveBorrowWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.aaveRepayWeth(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.aaveSupplyLst(1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotLocked.selector));
        vault.aaveWithdrawLst(1 ether);
    }

    function testRevertsWhenZeroAmount() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testRevertsWhenZeroAmountCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testRevertsWhenZeroAmountCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.pullWeth(0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.sendWeth(user1, 0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.sendLst(user1, 0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.pullLst(0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.aaveBorrowWeth(0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.aaveRepayWeth(0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.aaveSupplyLst(0);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAmount.selector));
        vault.aaveWithdrawLst(0);
    }

    function testRevertsWhenZeroAddress() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testRevertsWhenZeroAddressCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testRevertsWhenZeroAddressCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAddress.selector));
        vault.sendWeth(address(0), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroAddress.selector));
        vault.sendLst(address(0), 1 ether);
    }

    function testStakeWethRevertsWhenLessThanMin() public {
        _setupStandardDeposit();

        bytes memory callbackData = abi.encodeWithSelector(this._testStakeWethRevertsWhenLessThanMinCallback.selector);
        _depositToVault(user1, 5 ether, 0, callbackData);
    }

    function _testStakeWethRevertsWhenLessThanMinCallback() external {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.AmountLessThanMin.selector));
        vault.stakeWeth(0.001 ether);
    }

    function testSendingEthToVaultReverts() public {
        _setupStandardDeposit();

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.SenderNotWethContract.selector));
        payable(address(vault)).transfer(1 ether);
    }

    receive() external payable {}
}
