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

    function testGrowthInLstRateIsImmediatelyReflected() public {
        IPriceOracle priceOracle = IPriceOracle(vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle());
        uint256 donateAmount = 100_000 ether;
        uint256 lstRateBefore = LST.getRate();
        uint256 lstPriceBefore = priceOracle.getAssetPrice(address(LST));
        uint256 ethPrice = priceOracle.getAssetPrice(address(WETH));
        VaultSnapshot.Data memory stateBefore = vault.getVaultSnapshot();

        vm.deal(LST_OPERATOR, donateAmount);

        vm.prank(LST_OPERATOR);
        LST.donate{value: donateAmount}();

        uint256 lstRateAfter = LST.getRate();
        uint256 lstPriceAfter = priceOracle.getAssetPrice(address(LST));
        VaultSnapshot.Data memory stateAfter = vault.getVaultSnapshot();

        uint256 lstRateAfterComputed = lstPriceAfter * 1e18 / ethPrice;

        assertGt(lstRateAfter, lstRateBefore, "Rate should increase");
        assertGt(lstPriceAfter, lstPriceBefore, "Price should increase");

        // computed rate is accurate to 7 decimals since aave's base price uses 8 decimals
        assertApproxEqAbs(lstRateAfter, lstRateAfterComputed, 1e11, "Rate should be approximately equal");

        assertGt(stateAfter.netAssetValueInEth(), stateBefore.netAssetValueInEth(), "Net asset value should increase");
        assertGt(
            stateAfter.lstCollateralAmountInEth, stateBefore.lstCollateralAmountInEth, "LST collateral should increase"
        );
    }

    function testGrowthInLstRateExceedsMaxRatio() public {
        IPriceOracle priceOracle = IPriceOracle(vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle());
        IAaveCapoRateProvider rateProvider = vault.aaveCapoRateProvider();
        uint256 donateAmount = 10_000_000 ether;

        uint256 ethPrice = priceOracle.getAssetPrice(address(WETH));

        vm.deal(LST_OPERATOR, donateAmount);

        vm.prank(LST_OPERATOR);
        // Donate enough to exceed the CAPO max ratio
        LST.donate{value: donateAmount}();

        uint256 rateAfter = rateProvider.getRate();
        uint256 lstPriceAfter = priceOracle.getAssetPrice(address(LST));
        uint256 raterAfterComputed = lstPriceAfter * 1e18 / ethPrice;

        VaultSnapshot.Data memory stateAfter = vault.getVaultSnapshot();

        assertGt(LST.getRate(), rateAfter, "LST rate should be greater than the rate provider rate");

        // computed rate is accurate to 7 decimals since aave's base price uses 8 decimals
        assertApproxEqAbs(rateAfter, raterAfterComputed, 1e11, "Rate should be approximately equal");

        assertEq(
            stateAfter.lstCollateralAmountInEth,
            rateProvider.convertToAssets(stateAfter.lstCollateralAmount),
            "LST collateral amount in ETH should be using the rate provider rate"
        );
    }

    function testComputedHealthFactorMatchesAaveValue() public {
        _setupStandardDeposit();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = vault.AAVE_POOL().getUserAccountData(address(vault));

        // computed health factor is accurate to 7 decimals since aave's base price uses 8 decimals
        assertApproxEqAbs(healthFactor, vault.getHealthFactor(), 1e11, "Health factor should be equal");
    }

    function testOperationRevertsWithLstRateChange() public {
        _setupStandardDeposit();

        VaultSnapshot.Data memory snapshotBefore = vault.getVaultSnapshot();
        uint256 lstAmountToWithdraw = snapshotBefore.lstCollateralAmount / 10;

        bytes memory liquidationData =
            abi.encodeWithSelector(this._unwindAndChangeLstRate.selector, lstAmountToWithdraw);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.LstRateChanged.selector));
        vault.unwind(lstAmountToWithdraw, liquidationData);
    }

    function _unwindAndChangeLstRate(uint256 lstAmount) external returns (uint256 wethAmount) {
        // We simulate liqudation at the redemption rate
        wethAmount = LST.convertToAssets(lstAmount);

        // burn the LST
        LST.transfer(address(1), lstAmount);

        WETH.approve(address(vault), type(uint256).max);

        vm.deal(address(this), wethAmount);
        WETH.deposit{value: wethAmount}();

        uint256 donateAmount = 1_000 ether;

        vm.deal(LST_OPERATOR, donateAmount);

        vm.prank(LST_OPERATOR);
        LST.donate{value: donateAmount}();
    }

    function testProtocolFeePercent() public {
        uint256 athRateStart = vault.athRate();
        uint256 rateStart = vault.getRate();

        vm.startPrank(admin);
        vault.setProtocolFeePercent(0.01e18);
        vault.setTreasuryAddress(treasury);
        vm.stopPrank();

        uint256 rateStart2 = vault.getRate();
        _setupStandardDeposit();

        uint256 rateBefore = vault.getRate();

        //increase the rate
        _donateAaveLstATokensToVault(user1, 1 ether);

        uint256 rateAfter = vault.getRate();

        _setupStandardDeposit();

        _donateAaveLstATokensToVault(user1, 1 ether);

        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(1 ether);
        console.log("collateralInLst", collateralInLst);
        console.log("debtInEth", debtInEth);

        console.log("before withdraw");
        _withdrawFromVault(user1, 1 ether, "");
    }
}
