// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultDonateTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;

    function testDonateATokenForLstFromUserAddress() public {
        _setupStandardDeposit();

        uint256 donateAmount = 0.1 ether;

        // Get LST aToken address from the vault
        IERC20 lstAToken = vault.LST_A_TOKEN();

        vm.deal(user1, donateAmount);

        // Setup: First, the donator needs to get some LST and supply it to Aave to get aTokens
        vm.startPrank(user1);
        uint256 lstAmount = LST.deposit{value: donateAmount}();

        // Supply LST to Aave to get aTokens
        LST.approve(address(vault.AAVE_POOL()), lstAmount);
        vault.AAVE_POOL().supply(address(LST), lstAmount, user1, 0);

        uint256 aTokenBalance = lstAToken.balanceOf(user1);
        uint256 user1ATokenBalanceBefore = aTokenBalance;
        uint256 vaultATokenBalanceBefore = lstAToken.balanceOf(address(vault));

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        // Transfer aTokens directly to the vault
        lstAToken.transfer(address(vault), aTokenBalance);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        console.log("collateralAmountInEth before", snapshotBefore.lstCollateralAmountInEth);
        console.log("collateralAmountInEth after ", snapshotAfter.lstCollateralAmountInEth);

        console.log("netAssetValueInEth before", snapshotBefore.netAssetValueInEth());
        console.log("netAssetValueInEth after ", snapshotAfter.netAssetValueInEth());

        // Verify the transfer happened
        /* assertEq(
            lstAToken.balanceOf(user1),
            user1ATokenBalanceBefore - aTokenBalance,
            "Donator aToken balance should decrease"
        );
        assertEq(
            lstAToken.balanceOf(address(vault)),
            vaultATokenBalanceBefore + aTokenBalance,
            "Vault aToken balance should increase"
        );

        // The vault's LST collateral should increase because aTokens represent LST collateral in Aave
        assertGt(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth,
            "LST collateral should increase"
        ); */

        vm.stopPrank();
    }
}
