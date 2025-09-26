// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultTrustedRouter is LoopedSonicVaultBase {
    function setUp() public override {
        super.setUp();
        assertTrue(vault.isTrustedRouter(address(this)), "we are trusted router");

        vm.prank(admin);
        vault.removeTrustedRouter(address(this));
        assertFalse(vault.isTrustedRouter(address(this)), "we are not trusted router");
    }

    function testDepositReverts() public {
        bytes memory depositData = abi.encodeWithSelector(this._depositCallback.selector, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotTrustedRouter.selector));
        vault.deposit(user1, depositData);
    }

    function testWithdrawReverts() public {
        bytes memory withdrawData = abi.encodeWithSelector(this._withdrawCallback.selector, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.NotTrustedRouter.selector));
        vault.withdraw(1, withdrawData);
    }
}
