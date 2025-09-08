// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {BaseLoopedSonicRouter} from "../src/BaseLoopedSonicRouter.sol";
import {MockLoopedSonicRouter} from "./mocks/MockLoopedSonicRouter.sol";
import {LoopedSonicVaultBase} from "./LoopedSonicVaultBase.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBalancerVault} from "../src/interfaces/IBalancerVault.sol";

contract BaseLoopedSonicRouterTest is LoopedSonicVaultBase {
    MockLoopedSonicRouter public router;

    // Each call to vault.stakeWeth can result in the LST rounding in it's favor (1 wei)
    // In addition, aave will round down the collateral amount, so we account for that as well
    uint256 public constant NAV_DECREASE_TOLERANCE = MAX_LOOP_ITERATIONS + 1;

    uint256 public constant AAVE_FLASH_LOAN_FEE_BIPS = 5;
    uint256 public constant BIPS_DIVISOR = 10000;

    function setUp() public override {
        super.setUp();
        router = new MockLoopedSonicRouter(vault);
    }

    function testRouterConstructor() public view {
        assertEq(address(router.VAULT()), address(vault));
        assertEq(router.MAX_LOOP_ITERATIONS(), 20);

        assertEq(IERC20(address(WETH)).allowance(address(router), address(vault)), type(uint256).max);
        assertEq(IERC20(address(LST)).allowance(address(router), address(vault)), type(uint256).max);
    }

    function testRouterDepositSuccess() public {
        uint256 depositAmount = 10 ether;
        vm.deal(user1, depositAmount);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(user1);
        router.deposit{value: depositAmount}();

        uint256 sharesAfter = vault.balanceOf(user1);
        assertApproxEqAbs(sharesAfter, sharesBefore + depositAmount, NAV_DECREASE_TOLERANCE);
    }

    function testRouterDepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        router.deposit{value: 0}();
    }

    function testRouterDepositCallbackOnlyVault() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.NotVault.selector));
        router.depositCallback(1 ether);
    }

    function testRouterDepositNotEnoughLst() public {
        router.setLstAmountOutOverride(1);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.NotEnoughLst.selector));
        router.deposit{value: 1 ether}();
    }

    function testRouterWithdrawWithFlashLoanSuccess() public {
        uint256 shares = _setupStandardDeposit();
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(shares);
        uint256 wethSwappedAmount = vault.LST().convertToAssets(collateralInLst);
        uint256 flashLoanFee = (debtInEth * AAVE_FLASH_LOAN_FEE_BIPS) / BIPS_DIVISOR;

        uint256 expexctedWethAmountOut = vault.convertToAssets(shares) - flashLoanFee;

        uint256 wethBalanceBefore = WETH.balanceOf(user1);

        vm.prank(user1);
        vault.approve(address(router), shares);

        bytes memory convertData = abi.encode(wethSwappedAmount);

        vm.prank(user1);
        router.withdrawWithFlashLoan(shares, 0, convertData);

        uint256 wethBalanceAfter = WETH.balanceOf(user1);
        assertApproxEqAbs(wethBalanceAfter, wethBalanceBefore + expexctedWethAmountOut, 2);
        // Any rounding should be in favor of the vault
        assertLe(wethBalanceAfter, wethBalanceBefore + expexctedWethAmountOut);
    }

    function testRouterWithdrawSuccess() public {
        uint256 shares = _setupStandardDeposit() / 20;
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(shares);
        uint256 wethSwappedAmount = vault.LST().convertToAssets(collateralInLst);

        uint256 expexctedWethAmountOut = vault.convertToAssets(shares);

        uint256 wethBalanceBefore = WETH.balanceOf(user1);

        vm.prank(user1);
        vault.approve(address(router), shares);

        bytes memory convertData = abi.encode(wethSwappedAmount);

        vm.prank(user1);
        router.withdraw(shares, 0, convertData);

        uint256 wethBalanceAfter = WETH.balanceOf(user1);
        assertApproxEqAbs(wethBalanceAfter, wethBalanceBefore + expexctedWethAmountOut, 2);
        // Any rounding should be in favor of the vault
        assertLe(wethBalanceAfter, wethBalanceBefore + expexctedWethAmountOut);
    }

    function testWithdrawInsufficientShares() public {
        uint256 shares = 1000 ether;

        vm.prank(user1);
        vm.expectRevert();
        router.withdrawWithFlashLoan(shares, 0, abi.encode(1 ether));
    }

    function testWithdrawMinAmountNotMet() public {
        uint256 depositAmount = 10 ether;
        vm.deal(user1, depositAmount);

        vm.prank(user1);
        router.deposit{value: depositAmount}();

        uint256 shares = vault.balanceOf(user1);
        (uint256 collateralInLst, uint256 debtInEth) = vault.getCollateralAndDebtForShares(shares);
        uint256 wethSwappedAmount = vault.LST().convertToAssets(collateralInLst);
        uint256 flashLoanFee = (debtInEth * AAVE_FLASH_LOAN_FEE_BIPS) / BIPS_DIVISOR;

        uint256 expexctedWethAmountOut = vault.convertToAssets(shares) - flashLoanFee;

        vm.prank(user1);
        vault.approve(address(router), shares);

        bytes memory convertData = abi.encode(wethSwappedAmount);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.AmountOutBelowMin.selector));
        router.withdrawWithFlashLoan(shares, expexctedWethAmountOut + 1, convertData);
    }

    function testWithdrawCallbackOnlyVault() public {
        BaseLoopedSonicRouter.WithdrawParams memory params = BaseLoopedSonicRouter.WithdrawParams({
            recipient: user1,
            amountShares: 1 ether,
            minWethAmountOut: 0,
            collateralInLst: 1 ether,
            debtInEth: 1 ether,
            convertLstToWethData: abi.encode(1 ether)
        });

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.NotVault.selector));
        router.withdrawWithFlashLoanCallback(params, 0);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.NotVault.selector));
        router.withdrawCallback(params);
    }

    function testExecuteOperationOnlyAavePool() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.NotAavePool.selector));
        router.executeOperation(address(WETH), 1 ether, 0, address(router), "");
    }

    function testExecuteOperationBadInitiator() public {
        vm.prank(address(vault.AAVE_POOL()));
        vm.expectRevert(abi.encodeWithSelector(BaseLoopedSonicRouter.BadInitiator.selector));
        router.executeOperation(address(WETH), 1 ether, 0, user1, "");
    }
}
