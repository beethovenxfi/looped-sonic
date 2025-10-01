// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {AaveCapoRateProvider} from "../src/AaveCapoRateProvider.sol";
import {IMagpieRouterV3_1} from "../src/interfaces/IMagpieRouterV3_1.sol";
import {MagpieLoopedSonicRouter} from "../src/MagpieLoopedSonicRouter.sol";

contract LoopedSonicVaultScript is Script {
    address constant WETH = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38; // wS
    address constant LST = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955; // stS
    address constant AAVE_POOL = 0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    uint8 constant E_MODE_CATEGORY_ID = 1;
    address constant PRICE_CAP_ADAPTER = 0x5BA5D5213B47DFE020B1F8d6fB54Db3F74F9ea9a;
    uint256 constant INITIAL_TARGET_HEALTH_FACTOR = 1.3e18;
    uint256 constant INITIAL_ALLOWED_UNWIND_SLIPPAGE = 0.007e18; // 0.7%
    address constant ADMIN = 0x606681E47afC7869482660eCD61bd45B53523D83;
    address constant TREASURY = 0x26377CAB961c84F2d7b9d9e36D296a1C1c77C995;

    IMagpieRouterV3_1 constant MAGPIE_ROUTER = IMagpieRouterV3_1(0xc325856e5585823aaC0D1Fd46c35c608D95E65A9);

    function run()
        external
        returns (LoopedSonicVault vault, AaveCapoRateProvider aaveCapoRateProvider, MagpieLoopedSonicRouter router)
    {
        vm.startBroadcast();

        aaveCapoRateProvider = new AaveCapoRateProvider(LST, PRICE_CAP_ADAPTER);

        // Deploy the LoopedSonicVault contract
        vault = new LoopedSonicVault(
            WETH,
            LST,
            AAVE_POOL,
            E_MODE_CATEGORY_ID,
            address(aaveCapoRateProvider),
            INITIAL_TARGET_HEALTH_FACTOR,
            INITIAL_ALLOWED_UNWIND_SLIPPAGE,
            ADMIN,
            TREASURY
        );

        router = new MagpieLoopedSonicRouter(vault, MAGPIE_ROUTER);

        vault.addTrustedRouter(address(router));

        // default protocol fee is 10%
        vault.setProtocolFeePercent(0.01e18);

        vault.WETH().approve(address(vault), vault.INIT_AMOUNT());

        // initialize the vault
        vault.initialize();

        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("LoopedSonicVault deployed at:", address(vault));
        console.log("AaveCapoRateProvider deployed at:", address(aaveCapoRateProvider));
        console.log("MagpieLoopedSonicRouter deployed at:", address(router));
    }
}
