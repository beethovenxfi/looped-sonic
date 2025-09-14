// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ISonicStaking} from "../src/interfaces/ISonicStaking.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ILoopedSonicVault} from "../src/interfaces/ILoopedSonicVault.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPriceCapAdapter} from "../src/interfaces/IPriceCapAdapter.sol";
import {AaveCapoRateProvider} from "../src/AaveCapoRateProvider.sol";

contract LoopedSonicVaultBase is Test {
    using VaultSnapshot for VaultSnapshot.Data;
    using Address for address;

    ISonicStaking constant LST = ISonicStaking(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    address constant AAVE_POOL = address(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3);
    IWETH constant WETH = IWETH(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    address constant LST_ADMIN = address(0x6Daeb8BB06A7CF3475236C6c567029d333455E38);
    address constant LST_OPERATOR = address(0x6840Bd91417373Af296cc263e312DfEBcAb494ae);
    IPriceCapAdapter constant PRICE_CAP_ADAPTER = IPriceCapAdapter(0x5BA5D5213B47DFE020B1F8d6fB54Db3F74F9ea9a);
    uint8 constant E_MODE_CATEGORY_ID = 1;
    LoopedSonicVault public vault;
    AaveCapoRateProvider public aaveCapoRateProvider;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public treasury = makeAddr("treasury");

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant INIT_AMOUNT = 1 ether;
    uint256 public constant MAX_LOOP_ITERATIONS = 10;

    function setUp() public virtual {
        vm.createSelectFork("https://rpc.soniclabs.com", 45497827);

        aaveCapoRateProvider = new AaveCapoRateProvider(address(LST), address(PRICE_CAP_ADAPTER));

        vault = new LoopedSonicVault(
            address(WETH), address(LST), AAVE_POOL, E_MODE_CATEGORY_ID, address(aaveCapoRateProvider), admin
        );
        WETH.approve(address(vault), type(uint256).max);
        LST.approve(address(vault), type(uint256).max);

        _setupRoles();
        _setupInitialBalances();
        _initializeVault();
    }

    function _setupRoles() internal {
        vm.startPrank(admin);
        vault.grantRole(vault.OPERATOR_ROLE(), operator);
        vault.grantRole(vault.UNWIND_ROLE(), address(this));
        vm.stopPrank();
    }

    function _setupInitialBalances() internal {
        vm.deal(admin, INITIAL_BALANCE * 2);
        vm.deal(user1, INITIAL_BALANCE * 2);
        vm.deal(user2, INITIAL_BALANCE * 2);

        vm.prank(admin);
        WETH.deposit{value: INITIAL_BALANCE}();

        vm.prank(user1);
        WETH.deposit{value: INITIAL_BALANCE}();

        vm.prank(user2);
        WETH.deposit{value: INITIAL_BALANCE}();
    }

    function _initializeVault() internal virtual {
        vm.startPrank(admin);
        WETH.approve(address(vault), type(uint256).max);
        vault.initialize();
        vm.stopPrank();
    }

    function _depositToVault(
        address user,
        uint256 wethAmount,
        uint256 expectedShares,
        bytes memory optionalCallbackData
    ) internal returns (uint256 shares) {
        vm.prank(user);
        WETH.approve(address(this), wethAmount);

        WETH.transferFrom(user, address(this), wethAmount);

        bytes memory callbackData =
            abi.encodeWithSelector(this._depositCallback.selector, wethAmount, optionalCallbackData);
        uint256 sharesBefore = vault.balanceOf(user);

        vault.deposit(user, callbackData);

        shares = vault.balanceOf(user) - sharesBefore;

        if (expectedShares > 0) {
            assertApproxEqRel(shares, expectedShares, 0.01e18); // 1% tolerance
        }
    }

    function _withdrawFromVault(address user, uint256 sharesToRedeem, bytes memory optionalCallbackData) internal {
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        bytes memory callbackData = abi.encodeWithSelector(
            this._withdrawCallback.selector, user, collateralInLst, debtInEth, optionalCallbackData
        );

        vm.prank(user);
        vault.transfer(address(this), sharesToRedeem);

        vault.withdraw(sharesToRedeem, callbackData);
    }

    function _withdrawCallback(
        address user,
        uint256 collateralInLst,
        uint256 debtInEth,
        bytes memory optionalCallbackData
    ) external {
        if (debtInEth > 0) {
            vm.deal(address(this), debtInEth);
            WETH.deposit{value: debtInEth}();

            vault.pullWeth(debtInEth);
            vault.aaveRepayWeth(debtInEth);
        }

        vault.aaveWithdrawLst(collateralInLst);
        uint256 collateralInEth = vault.LST().convertToAssets(collateralInLst);

        // burn the LST
        vault.sendLst(address(1), collateralInLst);

        vm.deal(address(this), collateralInEth);
        WETH.deposit{value: collateralInEth}();

        WETH.transfer(user, collateralInEth);

        if (optionalCallbackData.length > 0) {
            address(this).functionCall(optionalCallbackData);
        }
    }

    function _setupStandardDeposit() internal returns (uint256 shares) {
        uint256 depositAmount = 10 ether;
        shares = _depositToVault(user1, depositAmount, 0, "");
    }

    function _depositCallback(uint256 initialAssets, bytes calldata optionalCallbackData) external {
        uint256 currentAssets = initialAssets;
        uint256 totalCollateral = 0;

        vault.pullWeth(initialAssets);

        for (uint256 i = 0; i < MAX_LOOP_ITERATIONS && currentAssets > 0; i++) {
            uint256 lstAmount = vault.stakeWeth(currentAssets);

            vault.aaveSupplyLst(lstAmount);

            totalCollateral += lstAmount;

            uint256 borrowAmount = vault.getBorrowAmountForLoopInEth();

            if (borrowAmount < vault.MIN_LST_DEPOSIT()) {
                break;
            }

            vault.aaveBorrowWeth(borrowAmount);

            currentAssets = borrowAmount;
        }

        if (optionalCallbackData.length > 0) {
            address(this).functionCall(optionalCallbackData);
        }
    }

    function _getUninitializedVault() internal returns (LoopedSonicVault) {
        return new LoopedSonicVault(
            address(WETH), address(LST), AAVE_POOL, E_MODE_CATEGORY_ID, address(aaveCapoRateProvider), admin
        );
    }

    function _attemptReentrancy() public {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.deposit(user1, abi.encodeWithSelector(this.emptyCallback.selector));

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.withdraw(1e18, abi.encodeWithSelector(this.emptyCallback.selector));

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.unwind(1e18, abi.encodeWithSelector(this.emptyCallback.selector));
    }

    function _attemptReadOnlyReentrancy() public {
        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.totalAssets();

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.convertToAssets(1e18);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.convertToShares(1e18);

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.getRate();

        vm.expectRevert(abi.encodeWithSelector(ILoopedSonicVault.Locked.selector));
        vault.getCollateralAndDebtForShares(1e18);
    }

    function _donateAaveLstATokensToVault(address fromUser, uint256 ethAmount) public returns (uint256 lstAmount) {
        vm.deal(fromUser, ethAmount);

        vm.startPrank(fromUser);

        lstAmount = LST.deposit{value: ethAmount}();
        LST.approve(address(vault.AAVE_POOL()), lstAmount);
        vault.AAVE_POOL().supply(address(LST), lstAmount, address(vault), 0);

        vm.stopPrank();
    }

    function _dealWethToAddress(address user, uint256 amount) internal {
        vm.deal(user, amount);
        vm.prank(user);
        WETH.deposit{value: amount}();
    }

    function emptyCallback() external {}
}
