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
        data.dataBefore = vault.getVaultSnapshot();
        uint256 invariantBefore = vault.totalAssets() * 1e18 / vault.totalSupply();
        uint256 expectedShares = vault.convertToShares(depositAmount);

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        WETH.transferFrom(user1, address(this), depositAmount);

        vm.expectEmit(true, true, false, false);
        emit ILoopedSonicVault.Deposit(address(this), user1, 0, 0);

        vault.deposit(user1, depositData);

        data.dataAfter = vault.getVaultSnapshot();
        uint256 sharesAfter = vault.balanceOf(user1);
        uint256 invariantAfter = vault.totalAssets() * 1e18 / vault.totalSupply();

        assertApproxEqAbs(
            data.navIncreaseEth(), depositAmount, NAV_DECREASE_TOLERANCE, "NAV should increase by the deposit amount"
        );

        assertEq(invariantAfter, invariantBefore, "Invariant should not change");
        assertApproxEqAbs(
            vault.totalSupply(),
            data.dataBefore.vaultTotalSupply + expectedShares,
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
        LoopedSonicVault uninitializedVault =
            new LoopedSonicVault(address(WETH), address(LST), AAVE_POOL, E_MODE_CATEGORY_ID, admin);

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

        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, depositAmount, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NavIncreaseBelowMin.selector));
        vault.deposit(user1, depositData);
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

    function _invalidDeposit(uint256 amount) external {
        // We do a single loop, which will leave the health factor higher than the target
        // causing a revert
        vault.pullWeth(amount);
        uint256 lstAmount = vault.stakeWeth(amount);

        vault.aaveSupplyLst(lstAmount);
    }
}
