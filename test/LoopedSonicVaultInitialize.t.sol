// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultInitializeTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;

    event Initialized(address indexed admin);

    // Override to skip initialization for these tests
    function _initializeVault() internal override {
        // Do not initialize - these tests will test the initialization process
    }

    function testInitializeSuccess() public {
        vm.prank(user1);
        WETH.approve(address(vault), INIT_AMOUNT);

        uint256 wethBalanceBefore = WETH.balanceOf(user1);
        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        assertFalse(vault.isInitialized(), "Vault should not be initialized");
        assertEq(snapshotBefore.vaultTotalSupply, 0, "Vault should have no shares before init");
        assertEq(snapshotBefore.lstCollateralAmount, 0, "Vault should have no LST collateral before init");
        assertEq(snapshotBefore.lstCollateralAmountInEth, 0, "Vault should have no LST collateral before init");
        assertEq(snapshotBefore.wethDebtAmount, 0, "Vault should have no WETH debt before init");
        assertEq(snapshotBefore.netAssetValueInEth(), 0, "Vault should have no NAV before init");

        vm.expectEmit(true, true, false, false);
        // Because of AAVE rounding, the nav may be 1 wei smaller than the init amount
        emit ILoopedSonicVault.Initialize(user1, address(1), 0, 0);

        vm.prank(user1);
        vault.initialize();

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();
        uint256 nav = snapshotAfter.netAssetValueInEth();

        assertTrue(vault.isInitialized(), "Vault should be initialized");
        assertEq(WETH.balanceOf(user1), wethBalanceBefore - INIT_AMOUNT, "user WETH balance should decrease");
        assertEq(WETH.balanceOf(address(vault)), 0, "Vault should not hold WETH after init");
        assertEq(LST.balanceOf(address(vault)), 0, "Vault should not hold LST after init");
        assertEq(snapshotAfter.vaultTotalSupply, nav, "Total supply should equal the nav");
        assertEq(vault.balanceOf(address(1)), snapshotAfter.vaultTotalSupply, "All initial shares should be burned");
        assertEq(
            snapshotAfter.lstCollateralAmount,
            LST.convertToShares(INIT_AMOUNT),
            "LST collateral should be equal to the init amount of eth staked"
        );
        assertEq(snapshotAfter.wethDebtAmount, 0, "WETH debt should be 0");
        assertApproxEqAbs(nav, INIT_AMOUNT, 1, "Nav should be equal to init amount");
        assertEq(vault.lastDonationTime(), block.timestamp, "Last donation time should be set");
    }

    function testInitializeRevertsIfAlreadyInitialized() public {
        vm.startPrank(user1);
        WETH.approve(address(vault), INIT_AMOUNT * 2);

        vault.initialize();
        assertTrue(vault.isInitialized(), "Vault should be initialized");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.AlreadyInitialized.selector));
        vault.initialize();

        vm.stopPrank();
    }

    function testInitializeRevertsWithoutApproval() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.initialize();
    }

    function testInitializeRevertsWithInsufficientApproval() public {
        vm.startPrank(user1);
        WETH.approve(address(vault), INIT_AMOUNT - 1);

        vm.expectRevert();
        vault.initialize();

        vm.stopPrank();
    }

    function testInitializeRevertsWithInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");

        vm.deal(poorUser, 0.5 ether);
        vm.startPrank(poorUser);
        WETH.deposit{value: 0.5 ether}();
        WETH.approve(address(vault), INIT_AMOUNT);

        vm.expectRevert();
        vault.initialize();

        vm.stopPrank();
    }
}
