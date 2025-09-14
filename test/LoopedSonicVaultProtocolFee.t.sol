// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {VaultSnapshotComparison} from "../src/libraries/VaultSnapshotComparison.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";
import "forge-std/Vm.sol";
import {AaveCapoRateProvider} from "../src/AaveCapoRateProvider.sol";
import {IAaveCapoRateProvider} from "../src/interfaces/IAaveCapoRateProvider.sol";
import {IPriceOracle} from "aave-v3-origin/interfaces/IPriceOracle.sol";

contract LoopedSonicVaultMiscTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    uint256 public constant PROTOCOL_FEE_PERCENT = 0.01e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        vault.setProtocolFeePercent(PROTOCOL_FEE_PERCENT);
        vault.setTreasuryAddress(treasury);
        vm.stopPrank();
    }

    function testProtocolFeePaidToTreasury() public {
        _setupStandardDeposit();

        uint256 rateBefore = vault.getRate();

        uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingShares, 0, "Pending shares should be 0 after deposit");

        //increase the rate
        _donateAaveLstATokensToVault(user1, 1 ether);

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingSharesAfter, pendingShares, "Pending shares should increase after donation");

        uint256 treasuryBalanceBefore = vault.balanceOf(treasury);

        _setupStandardDeposit();

        uint256 treasuryBalanceAfter = vault.balanceOf(treasury);

        assertEq(
            treasuryBalanceAfter,
            treasuryBalanceBefore + pendingSharesAfter,
            "Treasury balance should increase by pending shares"
        );

        uint256 pendingSharesLast = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingSharesLast, 0, "Pending shares should be 0 after deposit");
    }

    function testCorrectPendingProtocolFeeSharesToBeMinted() public {
        uint256 donationAmount = 1 ether;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 protocolFeePercent = PROTOCOL_FEE_PERCENT * i;
            vm.prank(admin);
            vault.setProtocolFeePercent(protocolFeePercent);

            _donateAaveLstATokensToVault(user1, donationAmount);

            uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();
            uint256 ethForShares = vault.convertToAssets(pendingShares);
            uint256 expectedProtocolFeeAmount = donationAmount * protocolFeePercent / 1e18;

            assertApproxEqAbs(ethForShares, expectedProtocolFeeAmount, 10 * i);
            assertLt(ethForShares, expectedProtocolFeeAmount, "vault should round down");

            _setupStandardDeposit();
        }
    }

    function testProtocolFeeGoesDownAsDebtAccrues() public {
        _setupStandardDeposit();

        _donateAaveLstATokensToVault(user1, 1 ether);

        uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        vm.warp(block.timestamp + 1 days);

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertLt(pendingSharesAfter, pendingShares, "Pending shares should decrease as debt accrues");

        uint256 treasuryBalanceBefore = vault.balanceOf(treasury);

        _setupStandardDeposit();

        uint256 treasuryBalanceAfter = vault.balanceOf(treasury);

        assertEq(
            treasuryBalanceAfter,
            treasuryBalanceBefore + pendingSharesAfter,
            "Treasury balance should increase by reduced pending shares"
        );
    }
}
