// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";

contract LoopedSonicVaultViewTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;

    function setUp() public override {
        super.setUp();
    }

    function testGetVaultSnapshotInitialState() public view {
        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();

        assertGt(snapshot.lstCollateralAmount, 0);
        assertGt(snapshot.lstCollateralAmountInEth, 0);
        assertEq(snapshot.wethDebtAmount, 0);
        assertGt(snapshot.vaultTotalSupply, 0);
        assertGt(snapshot.ltv, 0);
        assertGt(snapshot.liquidationThreshold, 0);
    }

    function testGetVaultSnapshotAfterDeposit() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();

        assertGt(snapshot.lstCollateralAmount, 0);
        assertGt(snapshot.lstCollateralAmountInEth, 0);
        assertGt(snapshot.wethDebtAmount, 0);
        assertGt(snapshot.vaultTotalSupply, 0);
        assertGt(snapshot.ltv, 0);
        assertGt(snapshot.liquidationThreshold, 0);
    }

    function testTotalAssets() public view {
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0);

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        assertEq(totalAssets, snapshot.netAssetValueInEth());
    }

    function testTotalAssetsAfterDeposit() public {
        uint256 totalAssetsBefore = vault.totalAssets();
        _setupStandardDeposit();
        uint256 totalAssetsAfter = vault.totalAssets();

        assertGt(totalAssetsAfter, totalAssetsBefore);
    }

    function testConvertToAssetsZeroShares() public view {
        uint256 assets = vault.convertToAssets(0);
        assertEq(assets, 0);
    }

    function testConvertToAssetsNonZeroShares() public view {
        uint256 shareAmount = 1 ether;
        uint256 assets = vault.convertToAssets(shareAmount);

        assertGt(assets, 0);

        uint256 expectedAssets = shareAmount * vault.totalAssets() / vault.totalSupply();
        assertEq(assets, expectedAssets);
    }

    function testConvertToSharesZeroAssets() public view {
        uint256 shares = vault.convertToShares(0);
        assertEq(shares, 0);
    }

    function testConvertToSharesNonZeroAssets() public view {
        uint256 assetAmount = 1 ether;
        uint256 shares = vault.convertToShares(assetAmount);

        assertGt(shares, 0);

        uint256 expectedShares = assetAmount * vault.totalSupply() / vault.totalAssets();
        assertEq(shares, expectedShares);
    }

    function testConvertToAssetsAndSharesRoundTrip() public view {
        uint256 originalShares = 1 ether;
        uint256 assets = vault.convertToAssets(originalShares);
        uint256 convertedShares = vault.convertToShares(assets);

        assertApproxEqAbs(convertedShares, originalShares, 1);
    }

    function testGetRate() public view {
        uint256 rate = vault.getRate();
        assertGt(rate, 0);

        uint256 expectedRate = vault.convertToAssets(1 ether);
        assertEq(rate, expectedRate);
    }

    function testGetRateAfterDeposit() public {
        uint256 rateBefore = vault.getRate();
        _setupStandardDeposit();
        uint256 rateAfter = vault.getRate();

        assertEq(rateAfter, rateBefore);
    }

    function testGetCollateralAndDebtForSharesZeroShares() public {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.ZeroShares.selector));
        vault.getCollateralAndDebtForShares(0);
    }

    function testGetCollateralAndDebtForSharesExceedsTotalSupply() public {
        uint256 totalSupply = vault.totalSupply();
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.SharesExceedTotalSupply.selector));
        vault.getCollateralAndDebtForShares(totalSupply + 1);
    }

    function testGetCollateralAndDebtForSharesValidShares() public view {
        uint256 shares = vault.totalSupply() / 2;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(shares);

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedCollateral = snapshot.proportionalCollateralInLst(shares);
        uint256 expectedDebt = snapshot.proportionalDebtInEth(shares);

        assertEq(collateralInLst, expectedCollateral);
        assertEq(debtInEth, expectedDebt);
    }

    function testGetSessionBalancesInitialState() public view {
        (uint256 wethSessionBalance, uint256 lstSessionBalance) = vault.getSessionBalances();

        assertEq(wethSessionBalance, 0);
        assertEq(lstSessionBalance, 0);
    }

    function testGetAaveLstCollateralAmount() public view {
        uint256 collateralAmount = vault.getAaveLstCollateralAmount();
        assertGt(collateralAmount, 0);

        uint256 expectedAmount = vault.LST_A_TOKEN().balanceOf(address(vault));
        assertEq(collateralAmount, expectedAmount);
    }

    function testGetAaveWethDebtAmount() public view {
        uint256 debtAmount = vault.getAaveWethDebtAmount();
        assertEq(debtAmount, 0);

        uint256 expectedAmount = vault.WETH_VARIABLE_DEBT_TOKEN().balanceOf(address(vault));
        assertEq(debtAmount, expectedAmount);
    }

    function testGetAaveWethDebtAmountAfterDeposit() public {
        _setupStandardDeposit();

        uint256 debtAmount = vault.getAaveWethDebtAmount();
        assertGt(debtAmount, 0);

        uint256 expectedAmount = vault.WETH_VARIABLE_DEBT_TOKEN().balanceOf(address(vault));
        assertEq(debtAmount, expectedAmount);
    }

    function testGetHealthFactor() public view {
        uint256 healthFactor = vault.getHealthFactor();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedHealthFactor = snapshot.healthFactor();

        assertEq(healthFactor, expectedHealthFactor);
    }

    function testGetHealthFactorAfterDeposit() public {
        _setupStandardDeposit();

        uint256 healthFactor = vault.getHealthFactor();
        assertGe(healthFactor, vault.MIN_TARGET_HEALTH_FACTOR());

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedHealthFactor = snapshot.healthFactor();

        assertEq(healthFactor, expectedHealthFactor);
    }

    function testGetBorrowAmountForLoopInEth() public view {
        uint256 borrowAmount = vault.getBorrowAmountForLoopInEth();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedAmount = snapshot.borrowAmountForLoopInEth(vault.targetHealthFactor());

        assertEq(borrowAmount, expectedAmount);
    }

    function testGetBorrowAmountForLoopInEthAfterDeposit() public {
        _setupStandardDeposit();

        uint256 borrowAmount = vault.getBorrowAmountForLoopInEth();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedAmount = snapshot.borrowAmountForLoopInEth(vault.targetHealthFactor());

        assertEq(borrowAmount, expectedAmount);
    }

    function testGetInvariant() public view {
        uint256 invariant = vault.getInvariant();
        assertGt(invariant, 0);

        uint256 expectedInvariant = vault.totalAssets() * 1e18 / vault.totalSupply();
        assertEq(invariant, expectedInvariant);
    }

    function testGetInvariantAfterDeposit() public {
        uint256 invariantBefore = vault.getInvariant();
        _setupStandardDeposit();
        uint256 invariantAfter = vault.getInvariant();

        assertEq(invariantAfter, invariantBefore);
    }

    function testViewFunctionConsistency() public view {
        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();

        assertEq(vault.totalAssets(), snapshot.netAssetValueInEth());
        assertEq(vault.getAaveLstCollateralAmount(), snapshot.lstCollateralAmount);
        assertEq(vault.getAaveWethDebtAmount(), snapshot.wethDebtAmount);
        assertEq(vault.getHealthFactor(), snapshot.healthFactor());
        assertEq(vault.getBorrowAmountForLoopInEth(), snapshot.borrowAmountForLoopInEth(vault.targetHealthFactor()));
    }

    function testViewFunctionConsistencyAfterDeposit() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();

        assertEq(vault.totalAssets(), snapshot.netAssetValueInEth());
        assertEq(vault.getAaveLstCollateralAmount(), snapshot.lstCollateralAmount);
        assertEq(vault.getAaveWethDebtAmount(), snapshot.wethDebtAmount);
        assertEq(vault.getHealthFactor(), snapshot.healthFactor());
        assertEq(vault.getBorrowAmountForLoopInEth(), snapshot.borrowAmountForLoopInEth(vault.targetHealthFactor()));
    }

    function testFuzzConvertToAssetsAndShares(uint256 amount) public view {
        amount = bound(amount, 1, vault.totalSupply());

        uint256 assets = vault.convertToAssets(amount);
        uint256 convertedShares = vault.convertToShares(assets);

        assertApproxEqAbs(convertedShares, amount, 1);
    }

    function testFuzzGetCollateralAndDebtForShares(uint256 shares) public view {
        shares = bound(shares, 1, vault.totalSupply());

        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(shares);

        VaultSnapshot.Data memory snapshot = vault.getVaultSnapshot();
        uint256 expectedCollateral = snapshot.proportionalCollateralInLst(shares);
        uint256 expectedDebt = snapshot.proportionalDebtInEth(shares);

        assertEq(collateralInLst, expectedCollateral);
        assertEq(debtInEth, expectedDebt);
    }

    function testConvertToAssetsWhenSupplyIsZero() public {
        uint256 lstAmount = 1 ether;
        LoopedSonicVault vault2 = _getUninitializedVault();

        uint256 assets = vault2.convertToAssets(lstAmount);

        assertEq(assets, lstAmount);
    }

    function testConvertToSharesWhenSupplyIsZero() public {
        uint256 amount = 1 ether;
        LoopedSonicVault vault2 = _getUninitializedVault();

        uint256 shares = vault2.convertToShares(amount);

        assertEq(shares, amount);
    }
}
