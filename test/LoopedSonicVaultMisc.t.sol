// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {VaultSnapshotComparison} from "../src/libraries/VaultSnapshotComparison.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";
import "forge-std/Vm.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {AaveCapoRateProvider} from "../src/AaveCapoRateProvider.sol";

contract LoopedSonicVaultMiscTest is LoopedSonicVaultBase {
    using VaultSnapshot for VaultSnapshot.Data;
    using VaultSnapshotComparison for VaultSnapshotComparison.Data;

    function testGrowthInLstRateIsImmediatelyReflected() public {
        IPriceOracle priceOracle = vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle();
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
        IPriceOracle priceOracle = vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle();
        uint256 donateAmount = 10_000_000 ether;

        AaveCapoRateProvider rateProvider = new AaveCapoRateProvider(address(LST), address(PRICE_CAP_ADAPTER));

        uint256 rateBefore = rateProvider.getRate();
        uint256 lstRateBefore = LST.getRate();

        vm.deal(LST_OPERATOR, donateAmount);

        vm.prank(LST_OPERATOR);
        LST.donate{value: donateAmount}();

        uint256 rateAfter = rateProvider.getRate();
        uint256 lstRateAfter = LST.getRate();

        console.log("rateBefore   ", rateBefore);
        console.log("lstRateBefore", lstRateBefore);
        console.log("rateAfter    ", rateAfter);
        console.log("lstRateAfter ", lstRateAfter);
    }
}
