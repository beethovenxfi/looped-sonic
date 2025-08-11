// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LSTVault} from "./LSTVault.sol";
import {AaveAccount} from "./libraries/AaveAccount.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IFlashLoanSimpleReceiver} from "./interfaces/IFlashLoanSimpleReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LstLoopDepositor is IFlashLoanSimpleReceiver {
    using AaveAccount for AaveAccount.Data;
    using SafeERC20 for IERC20;

    LSTVault public immutable vault;
    IBalancerVault public immutable balancerVault;

    uint256 public constant MAX_LOOP_ITERATIONS = 10;

    constructor(LSTVault _vault, IBalancerVault _balancerVault) {
        vault = _vault;
        balancerVault = _balancerVault;

        IERC20(address(vault.WETH())).approve(address(vault), type(uint256).max);
        IERC20(address(vault.LST())).approve(address(vault), type(uint256).max);

        IERC20(address(vault.WETH())).approve(address(balancerVault), type(uint256).max);
        IERC20(address(vault.LST())).approve(address(balancerVault), type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "Not vault");
        _;
    }

    function deposit() external payable {
        IWETH(address(vault.WETH())).deposit{value: msg.value}();

        vault.deposit(msg.sender, abi.encodeCall(LstLoopDepositor.depositCallback, (msg.value)));
    }

    function depositCallback(uint256 initialAssets) external onlyVault {
        uint256 currentAssets = initialAssets;
        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;

        vault.pullWETH(initialAssets);

        for (uint256 i = 0; i < MAX_LOOP_ITERATIONS && currentAssets > 0; i++) {
            uint256 lstAmount = vault.stakeWETH(currentAssets);

            vault.aaveSupplyLST(lstAmount);

            totalCollateral += lstAmount;

            uint256 borrowAmount = _getAmountOfWethToBorrow();

            if (borrowAmount < vault.MIN_LST_DEPOSIT()) {
                break;
            }

            vault.aaveBorrowWETH(borrowAmount);

            totalDebt += borrowAmount;
            currentAssets = borrowAmount;
        }

        //emit PositionLooped(MAX_LOOP_ITERATIONS, totalCollateral, totalDebt);
    }

    function withdraw(uint256 amountShares) external {
        // The vault will burn shares from this contract, so we transfer them here immediately
        vault.transferFrom(msg.sender, address(this), amountShares);

        AaveAccount.Data memory aaveAccount = vault.getVaultAaveAccountData();
        uint256 totalSupply = vault.totalSupply();
        uint256 collateralInLST = aaveAccount.proportionalCollateralInLST(amountShares, totalSupply);
        uint256 debtInETH = aaveAccount.proportionalDebtInETH(amountShares, totalSupply);

        vault.aavePool().flashLoanSimple(
            address(this), address(vault.WETH()), debtInETH, abi.encode(msg.sender, amountShares, collateralInLST), 0
        );
    }

    function executeOperation(
        address asset,
        uint256 debtInETH,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(vault.aavePool()), "NOT_POOL");
        require(initiator == address(this), "BAD_INITIATOR");

        (address recipient, uint256 amountShares, uint256 collateralInLST) =
            abi.decode(params, (address, uint256, uint256));

        vault.withdraw(
            amountShares,
            abi.encodeCall(
                LstLoopDepositor.withdrawCallback, (recipient, amountShares, collateralInLST, debtInETH, premium)
            )
        );

        // pay back the flashloan
        IERC20(asset).approve(address(vault.aavePool()), debtInETH + premium);

        return true;
    }

    function withdrawCallback(
        address recipient,
        uint256 amountShares,
        uint256 collateralInLST,
        uint256 debtInETH,
        uint256 flashLoanFee
    ) external onlyVault {
        vault.pullWETH(debtInETH);

        vault.aaveRepayWETH(debtInETH);

        vault.aaveWithdrawLST(collateralInLST);

        vault.sendLST(address(this), collateralInLST);

        uint256 redemptionAmount = vault.LST().convertToAssets(collateralInLST);
        console.log("collateralInLST", collateralInLST);

        uint256 wethOut = balancerVault.swap(
            IBalancerVault.SingleSwap({
                poolId: 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: address(vault.LST()),
                assetOut: address(vault.WETH()),
                amount: collateralInLST,
                userData: ""
            }),
            IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            0,
            type(uint256).max
        );

        console.log("WETH out", wethOut);
        console.log("debtInETH", debtInETH);
        console.log("diff", wethOut - debtInETH);

        uint256 amountToRecipient = wethOut - debtInETH - flashLoanFee;

        console.log("amountToRecipient", amountToRecipient);
        console.log("redemptionAmount", redemptionAmount - debtInETH - flashLoanFee);

        // amountToRecipient 490,693_825_747_729_828_432_025
        // redemptionAmount  499,437_528_179_624_931_668_457

        // 157,743_246_614_722_991_068_698

        vault.WETH().transfer(recipient, amountToRecipient);
    }

    function _getAmountOfWethToBorrow() internal view returns (uint256) {
        AaveAccount.Data memory aaveAccount = vault.getVaultAaveAccountData();
        uint256 targetHealthFactor = vault.targetHealthFactor();
        uint256 availableBorrowInETH = aaveAccount.baseToETH(aaveAccount.availableBorrowsBase);
        uint256 debtInETH = aaveAccount.baseToETH(aaveAccount.totalDebtBase);

        if (aaveAccount.healthFactor < targetHealthFactor || availableBorrowInETH == 0) {
            return 0;
        }

        uint256 borrowAmount = (availableBorrowInETH * 0.95e18) / 1e18;

        if (debtInETH > 0) {
            // We calculate the amount we'd need to borrow to reach the target health factor
            // considering we'd deposit that amount back into the pool as collateral
            uint256 targetAmount = ((aaveAccount.healthFactor - targetHealthFactor) * debtInETH)
                / (targetHealthFactor - aaveAccount.liquidationThresholdScaled18());

            if (targetAmount < borrowAmount) {
                // In this instance we'll exceed the target health factor if we borrow the max amount,
                // so we return the target amount
                return targetAmount;
            }
        }

        return borrowAmount;
    }

    receive() external payable {}
}
