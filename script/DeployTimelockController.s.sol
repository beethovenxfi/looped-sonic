// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Script} from "forge-std/Script.sol";

contract DeployTimelockController is Script {
    address constant DAO_MSIG = 0x6Daeb8BB06A7CF3475236C6c567029d333455E38;

    function run() external returns (TimelockController) {
        vm.startBroadcast();

        // Deploy admin timelock (24hrs delay) that becomes admin of loops
        address[] memory adminProposers = new address[](1);
        adminProposers[0] = DAO_MSIG;
        TimelockController adminTimelock = new TimelockController(24 hours, adminProposers, adminProposers, address(0));

        vm.stopBroadcast();
        return adminTimelock;
    }
}
