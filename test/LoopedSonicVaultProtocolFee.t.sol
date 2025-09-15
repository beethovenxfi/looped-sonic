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

contract LoopedSonicVaultProtocolFeeTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    uint256 public constant PROTOCOL_FEE_PERCENT_BPS = 100; // 1%

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        vault.setProtocolFeePercentBps(PROTOCOL_FEE_PERCENT_BPS);
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

        assertApproxEqAbs(vault.getRate(), vault.athRate(), 1, "ath rate should be updated");
    }

    function testCorrectPendingProtocolFeeSharesToBeMinted() public {
        uint256 donationAmount = 1 ether;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 protocolFeePercentBps = PROTOCOL_FEE_PERCENT_BPS * i;
            vm.prank(admin);
            vault.setProtocolFeePercentBps(protocolFeePercentBps);

            _donateAaveLstATokensToVault(user1, donationAmount);

            uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();
            uint256 ethForShares = vault.convertToAssets(pendingShares);
            uint256 expectedProtocolFeeAmount = donationAmount * vault.protocolFeePercent() / 1e18;

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

    function testFuzzProtocolFeeAlwaysRoundsDown(uint256 protocolFeePercentBps, uint256 donateAmount) public {
        uint256 maxDonateAmount = 10_000_000 ether;
        protocolFeePercentBps = bound(protocolFeePercentBps, 0, 5000);
        donateAmount = bound(donateAmount, 0.01 ether, maxDonateAmount);

        _setupStandardDeposit();

        vm.prank(admin);
        vault.setProtocolFeePercentBps(protocolFeePercentBps);

        _donateAaveLstATokensToVault(user1, donateAmount);

        uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();
        uint256 ethForShares = vault.convertToAssets(pendingShares);
        uint256 expectedProtocolFeeAmount = donateAmount * vault.protocolFeePercent() / 1e18;

        assertApproxEqAbs(ethForShares, expectedProtocolFeeAmount, 1e12);
        assertLe(ethForShares, expectedProtocolFeeAmount, "protocol fee should round down");
    }

    function testProtocolFeeNotChargedTwice() public {
        _setupStandardDeposit();

        _donateAaveLstATokensToVault(user1, 1 ether);

        uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingShares, 0, "Pending shares should be greater than 0 after donate");

        _setupStandardDeposit();

        pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingShares, 0, "Pending shares should be 0 after deposit");

        // accrue debt, lower the rate
        vm.warp(block.timestamp + 365 days);

        assertLt(vault.getRate(), vault.athRate(), "Rate should be less than athRate");

        _donateAaveLstATokensToVault(user1, 1 ether);

        pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingShares, 0, "Pending shares should be 0 since rate is less than athRate");
    }

    function testProtocolFeeChargedOnLstRateGrowth() public {
        _setupStandardDeposit();

        uint256 pendingSharesBefore = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingSharesBefore, 0, "Pending shares should be 0 after deposit");

        _donateToLst(1 ether);

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingSharesAfter, 0, "Pending shares should be greater than 0 after LST rate growth");
    }

    function testProtocolFeesChargedOnWithdraw() public {
        _setupStandardDeposit();

        _donateToLst(1 ether);

        uint256 pendingSharesBefore = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingSharesBefore, 0, "Pending shares should be greater than 0 after donate");

        _withdrawFromVault(user1, 1 ether, "");

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingSharesAfter, 0, "Pending shares should be 0 after withdraw");
        assertEq(vault.balanceOf(treasury), pendingSharesBefore, "Treasury balance should increase by pending shares");
        assertApproxEqAbs(vault.getRate(), vault.athRate(), 1, "ath rate should be updated");
    }

    function testProtocolFeesNotChargedOnUnwind() public {
        _setupStandardDeposit();

        _donateToLst(1 ether);

        uint256 pendingSharesBefore = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingSharesBefore, 0, "Pending shares should be greater than 0 after donate");

        _unwindFromVault(1 ether);

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingSharesAfter, pendingSharesBefore, "Pending shares should be the same after unwind");
    }

    function testPaysProtocolFeesBeforePercentageChange() public {
        _setupStandardDeposit();

        _donateAaveLstATokensToVault(user1, 1 ether);

        uint256 pendingShares = vault.getPendingProtocolFeeSharesToBeMinted();

        assertGt(pendingShares, 0, "Pending shares should be greater than 0 after donate");

        vm.prank(admin);
        vault.setProtocolFeePercentBps(PROTOCOL_FEE_PERCENT_BPS * 2);

        uint256 pendingSharesAfter = vault.getPendingProtocolFeeSharesToBeMinted();

        assertEq(pendingSharesAfter, 0, "Pending shares should be 0 after percentage change");

        assertEq(vault.balanceOf(treasury), pendingShares, "Treasury balance should increase by pending shares before");
    }
}
