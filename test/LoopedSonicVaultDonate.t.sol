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

    address public constant USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant USDC_WHALE = 0xA4E471dbfe8C95d4c44f520b19CEe436c01c3267;

    function testDonatingATokenIncreasesCollateralAndNav() public {
        _setupStandardDeposit();

        uint256 donateAmount = 1 ether;
        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        _donateAaveLstATokensToVault(user1, donateAmount);

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertApproxEqAbs(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth + donateAmount,
            1,
            "LST collateral should increase by the donate amount"
        );

        assertApproxEqAbs(
            snapshotAfter.netAssetValueInEth(),
            snapshotBefore.netAssetValueInEth() + donateAmount,
            1,
            "Nav should increase by the donate amount"
        );

        assertTrue(snapshotAfter.healthFactor() > snapshotBefore.healthFactor(), "Health factor should increase");
    }

    function testDonatingUsdcHasNoEffect() public {
        _setupStandardDeposit();

        uint256 usdcAmount = 1_000_000e6;

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();

        vm.startPrank(USDC_WHALE);
        IERC20(USDC).approve(address(vault.AAVE_POOL()), usdcAmount);
        vault.AAVE_POOL().supply(USDC, usdcAmount, address(vault), 0);
        vm.stopPrank();

        VaultSnapshot.Data memory snapshotAfter = vault.getVaultSnapshot();

        assertEq(
            snapshotAfter.lstCollateralAmountInEth,
            snapshotBefore.lstCollateralAmountInEth,
            "LST collateral should not change"
        );
        assertEq(snapshotAfter.netAssetValueInEth(), snapshotBefore.netAssetValueInEth(), "Nav should not change");
        assertEq(snapshotAfter.healthFactor(), snapshotBefore.healthFactor(), "Health factor should not change");
    }
}
