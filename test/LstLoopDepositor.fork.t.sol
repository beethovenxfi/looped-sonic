// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {BalancerLoopedSonicRouter} from "./mocks/BalancerLoopedSonicRouter.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IBalancerVault} from "../src/interfaces/IBalancerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISonicStaking} from "../src/interfaces/ISonicStaking.sol";

contract LstLoopDepositorForkTest is Test {
    using VaultSnapshot for VaultSnapshot.Data;

    LoopedSonicVault public vault;
    BalancerLoopedSonicRouter public depositor;

    ISonicStaking constant STAKED_SONIC = ISonicStaking(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    address constant AAVE_POOL = address(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3);
    IWETH constant WSONIC = IWETH(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    address constant BALANCER_VAULT = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address constant OWNER = address(0x5);
    uint8 constant E_MODE_CATEGORY_ID = 1;

    function setUp() public {
        vm.createSelectFork("https://rpc.soniclabs.com", 41170977);

        // Deploy vault
        vault = new LoopedSonicVault(address(WSONIC), address(STAKED_SONIC), AAVE_POOL, E_MODE_CATEGORY_ID, OWNER);

        // Deploy depositor
        depositor = new BalancerLoopedSonicRouter(vault, IBalancerVault(BALANCER_VAULT));

        // Give test account some S tokens (native token)
        vm.deal(address(this), 100_000_000 ether);
        vm.deal(OWNER, 100 ether);

        // Initialize vault
        vm.startPrank(OWNER);

        WSONIC.approve(address(vault), type(uint256).max);
        WSONIC.approve(address(depositor), type(uint256).max);

        WSONIC.deposit{value: 10 ether}();

        vault.initialize();
        vm.stopPrank();

        console.log("Vault total assets after init:", vault.totalAssets());
    }

    function testForkDeposit() public {
        uint256 depositAmount = 10 ether;
        uint256 initialBalance = address(this).balance;
        uint256 initialTotalAssets = vault.totalAssets();

        // Deposit into depositor which will execute loop strategy
        depositor.deposit{value: depositAmount}();

        // Verify balance changed
        assertEq(address(this).balance, initialBalance - depositAmount);

        // Verify vault received and processed the deposit
        uint256 finalTotalAssets = vault.totalAssets();
        assertTrue(finalTotalAssets > initialTotalAssets);

        console.log("Deposit successful: deposited", depositAmount);
        console.log("Initial total assets:", initialTotalAssets);
        console.log("Final total assets:", finalTotalAssets);
        console.log("Assets increase:", finalTotalAssets - initialTotalAssets);

        VaultSnapshot.Data memory aaveAccount = vault.getVaultSnapshot();
        console.log("health factor", aaveAccount.healthFactor());
        console.log("total collateral base", aaveAccount.lstCollateralAmount);
        console.log("available borrows base", aaveAccount.availableBorrowsInEth());
        console.log("total debt base", aaveAccount.wethDebtAmount);
        console.log("net asset value in ETH", aaveAccount.netAssetValueInEth());
        //console.log("collateral in ETH", aaveAccount.lstToEth(aaveAccount.lstCollateralAmount));
        console.log("debt in ETH", aaveAccount.wethDebtAmount);
    }

    function testForkWithdraw() public {
        uint256 depositAmount = 1_000_000 ether;
        uint256 initialBalance = address(this).balance;
        uint256 initialTotalAssets = vault.totalAssets();

        // Deposit into depositor which will execute loop strategy
        depositor.deposit{value: depositAmount}();

        WSONIC.deposit{value: 10_000 ether}();
        WSONIC.transfer(address(depositor), 10_000 ether);

        //console.log("STAKED_SONIC balance of depositor", STAKED_SONIC.balanceOf(address(depositor)));

        console.log("value of 50k shares", vault.convertToAssets(50_000 ether));

        // Withdraw from depositor
        vault.approve(address(depositor), type(uint256).max);
        depositor.withdraw(50_000 ether, 0, "");

        // Verify balance changed
        //assertEq(address(this).balance, initialBalance + depositAmount);

        // Verify vault received and processed the deposit
    }

    /* function testForkDepositWithHealthFactor() public {
        uint256 depositAmount = 5 ether;

        // Get initial health factor
        uint256 initialHealthFactor = vault.getVaultAaveAccountData().healthFactor;

        // Execute deposit
        depositor.deposit{value: depositAmount}();

        // Get final health factor
        uint256 finalHealthFactor = vault.getVaultAaveAccountData().healthFactor;

        // Health factor should remain above target (1.3e18)
        assertTrue(finalHealthFactor >= vault.targetHealthFactor());

        console.log("Initial health factor:", initialHealthFactor);
        console.log("Final health factor:", finalHealthFactor);
        console.log("Target health factor:", vault.targetHealthFactor());
    } */
}
