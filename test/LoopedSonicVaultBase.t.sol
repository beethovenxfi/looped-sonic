// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {LoopedSonicVault} from "../src/LoopedSonicVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ISonicStaking} from "../src/interfaces/ISonicStaking.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {VaultSnapshot} from "../src/libraries/VaultSnapshot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract LoopedSonicVaultBase is Test {
    using VaultSnapshot for VaultSnapshot.Data;
    using Address for address;

    ISonicStaking constant LST = ISonicStaking(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    address constant AAVE_POOL = address(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3);
    IWETH constant WETH = IWETH(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    uint8 constant E_MODE_CATEGORY_ID = 1;
    LoopedSonicVault public vault;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public donator = makeAddr("donator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant INIT_AMOUNT = 1 ether;
    uint256 public constant MAX_LOOP_ITERATIONS = 10;

    function setUp() public virtual {
        vm.createSelectFork("https://rpc.soniclabs.com", 41170977);

        vault = new LoopedSonicVault(address(WETH), address(LST), AAVE_POOL, E_MODE_CATEGORY_ID, admin);
        WETH.approve(address(vault), type(uint256).max);
        LST.approve(address(vault), type(uint256).max);

        _setupRoles();
        _setupInitialBalances();
        _initializeVault();
    }

    function _setupRoles() internal {
        vm.startPrank(admin);
        vault.grantRole(vault.OPERATOR_ROLE(), operator);
        vault.grantRole(vault.DONATOR_ROLE(), donator);
        vm.stopPrank();
    }

    function _setupInitialBalances() internal {
        vm.deal(admin, INITIAL_BALANCE * 2);
        vm.deal(user1, INITIAL_BALANCE * 2);
        vm.deal(user2, INITIAL_BALANCE * 2);
        vm.deal(donator, INITIAL_BALANCE * 2);

        vm.prank(admin);
        WETH.deposit{value: INITIAL_BALANCE}();

        vm.prank(user1);
        WETH.deposit{value: INITIAL_BALANCE}();

        vm.prank(user2);
        WETH.deposit{value: INITIAL_BALANCE}();

        vm.prank(donator);
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

    function _withdrawFromVault(address user, uint256 sharesToRedeem) internal {
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(sharesToRedeem);

        bytes memory callbackData =
            abi.encodeWithSelector(this._withdrawCallback.selector, user, collateralInLst, debtInEth);

        vm.prank(user);
        vault.transfer(address(this), sharesToRedeem);

        vault.withdraw(sharesToRedeem, callbackData);
    }

    function _withdrawCallback(address user, uint256 collateralInLst, uint256 debtInEth) external {
        vm.deal(address(this), debtInEth);
        WETH.deposit{value: debtInEth}();

        vault.pullWeth(debtInEth);

        vault.aaveRepayWeth(debtInEth);

        vault.aaveWithdrawLst(collateralInLst);
        uint256 collateralInEth = vault.LST().convertToAssets(collateralInLst);

        // burn the LST
        vault.sendLst(address(1), collateralInLst);

        vm.deal(address(this), collateralInEth);
        WETH.deposit{value: collateralInEth}();

        WETH.transfer(user, collateralInEth);
    }

    function _setupStandardDeposit() internal returns (uint256 shares) {
        uint256 depositAmount = 10 ether;
        shares = _depositToVault(user1, depositAmount, 0, "");
    }

    function _depositCallback(uint256 initialAssets, bytes calldata optionalCallbackData) external {
        uint256 currentAssets = initialAssets;
        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;

        vault.pullWeth(initialAssets);

        for (uint256 i = 0; i < MAX_LOOP_ITERATIONS && currentAssets > 0; i++) {
            uint256 minLstAmount = vault.LST().convertToShares(currentAssets);
            uint256 lstAmount = vault.stakeWeth(currentAssets);

            // The router implementation must ensure that the amount of LST received is at least the amount of
            // shares that would be received if the WETH was staked
            require(lstAmount >= minLstAmount, "LST amount out too low");

            vault.aaveSupplyLst(lstAmount);

            totalCollateral += lstAmount;

            uint256 borrowAmount = _getAmountOfWethToBorrow();

            if (borrowAmount < vault.MIN_LST_DEPOSIT()) {
                break;
            }

            vault.aaveBorrowWeth(borrowAmount);

            totalDebt += borrowAmount;
            currentAssets = borrowAmount;
        }

        if (optionalCallbackData.length > 0) {
            address(this).functionCall(optionalCallbackData);
        }
    }

    function _getAmountOfWethToBorrow() internal view returns (uint256) {
        VaultSnapshot.Data memory aaveAccount = vault.getVaultSnapshot();
        uint256 targetHealthFactor = vault.targetHealthFactor();
        uint256 availableBorrowInEth = aaveAccount.availableBorrowsInEth();
        uint256 debtInEth = aaveAccount.wethDebtAmount;

        if (aaveAccount.healthFactor() < targetHealthFactor || availableBorrowInEth == 0) {
            return 0;
        }

        uint256 borrowAmount = (availableBorrowInEth * 0.95e18) / 1e18;

        if (debtInEth > 0) {
            // We calculate the amount we'd need to borrow to reach the target health factor
            // considering we'd deposit that amount back into the pool as collateral
            uint256 targetAmount = ((aaveAccount.healthFactor() - targetHealthFactor) * debtInEth)
                / (targetHealthFactor - aaveAccount.liquidationThresholdScaled18());

            if (targetAmount < borrowAmount) {
                // In this instance we'll exceed the target health factor if we borrow the max amount,
                // so we return the target amount
                return targetAmount;
            }
        }

        return borrowAmount;
    }

    function _getLstPrice() internal view returns (uint256) {
        return vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle().getAssetPrice(address(LST));
    }

    function _getEthPrice() internal view returns (uint256) {
        return vault.AAVE_POOL().ADDRESSES_PROVIDER().getPriceOracle().getAssetPrice(address(WETH));
    }

    function _convertBaseAmountToLst(uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / _getLstPrice();
    }

    function _convertBaseAmountToEth(uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / _getEthPrice();
    }
}
