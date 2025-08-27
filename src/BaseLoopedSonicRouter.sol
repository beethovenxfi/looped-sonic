// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LoopedSonicVault} from "./LoopedSonicVault.sol";
import {VaultSnapshot} from "./libraries/VaultSnapshot.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IFlashLoanSimpleReceiver} from "./interfaces/IFlashLoanSimpleReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseLoopedSonicRouter is IFlashLoanSimpleReceiver {
    using VaultSnapshot for VaultSnapshot.Data;
    using SafeERC20 for IERC20;

    LoopedSonicVault public immutable VAULT;

    uint256 public constant MAX_LOOP_ITERATIONS = 10;

    constructor(LoopedSonicVault _vault) {
        VAULT = _vault;

        IERC20(address(VAULT.WETH())).approve(address(VAULT), type(uint256).max);
        IERC20(address(VAULT.LST())).approve(address(VAULT), type(uint256).max);
    }

    function convertWethToLst(uint256 wethAmount) internal virtual returns (uint256);
    function convertLstToWeth(uint256 lstCollateralAmount, bytes memory data) internal virtual returns (uint256);

    modifier onlyVault() {
        require(msg.sender == address(VAULT), "Not vault");
        _;
    }

    function deposit() external payable {
        IWETH(address(VAULT.WETH())).deposit{value: msg.value}();

        VAULT.deposit(msg.sender, abi.encodeCall(BaseLoopedSonicRouter.depositCallback, (msg.value)));
    }

    function depositCallback(uint256 initialAssets) external onlyVault {
        uint256 currentAssets = initialAssets;
        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;

        VAULT.pullWeth(initialAssets);

        for (uint256 i = 0; i < MAX_LOOP_ITERATIONS && currentAssets > 0; i++) {
            uint256 minLstAmount = VAULT.LST().convertToShares(currentAssets);
            uint256 lstAmount = convertWethToLst(currentAssets);

            // The router implementation must ensure that the amount of LST received is at least the amount of
            // shares that would be received if the WETH was staked
            require(lstAmount >= minLstAmount, "LST amount out too low");

            VAULT.aaveSupplyLst(lstAmount);

            totalCollateral += lstAmount;

            uint256 borrowAmount = _getAmountOfWethToBorrow();

            if (borrowAmount < VAULT.MIN_LST_DEPOSIT()) {
                break;
            }

            VAULT.aaveBorrowWeth(borrowAmount);

            totalDebt += borrowAmount;
            currentAssets = borrowAmount;
        }

        //emit PositionLooped(MAX_LOOP_ITERATIONS, totalCollateral, totalDebt);
    }

    struct WithdrawParams {
        address recipient;
        uint256 amountShares;
        uint256 minWethAmountOut;
        uint256 collateralInLst;
        uint256 debtInEth;
        bytes convertLstToWethData;
    }

    function withdraw(uint256 amountShares, uint256 minWethAmountOut, bytes memory convertLstToWethData) external {
        // The vault will burn shares from this contract, so we transfer them here immediately
        IERC20(address(VAULT)).safeTransferFrom(msg.sender, address(this), amountShares);

        (uint256 collateralInLst, uint256 debtInEth) = VAULT.getCollateralAndDebtForShares(amountShares);

        WithdrawParams memory params = WithdrawParams({
            recipient: msg.sender,
            amountShares: amountShares,
            minWethAmountOut: minWethAmountOut,
            collateralInLst: collateralInLst,
            debtInEth: debtInEth,
            convertLstToWethData: convertLstToWethData
        });

        VAULT.AAVE_POOL().flashLoanSimple(address(this), address(VAULT.WETH()), params.debtInEth, abi.encode(params), 0);
    }

    function executeOperation(
        address asset,
        uint256 flashLoanAmount,
        uint256 flashLoanFee,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(VAULT.AAVE_POOL()), "NOT_POOL");
        require(initiator == address(this), "BAD_INITIATOR");

        WithdrawParams memory withdrawParams = abi.decode(params, (WithdrawParams));

        VAULT.withdraw(
            withdrawParams.amountShares,
            abi.encodeCall(BaseLoopedSonicRouter.withdrawCallback, (withdrawParams, flashLoanFee))
        );

        // Allow aave to pull the funds to pay back the flashloan
        IERC20(asset).approve(address(VAULT.AAVE_POOL()), flashLoanAmount + flashLoanFee);

        return true;
    }

    function withdrawCallback(WithdrawParams memory params, uint256 flashLoanFee) external onlyVault {
        VAULT.pullWeth(params.debtInEth);

        VAULT.aaveRepayWeth(params.debtInEth);

        VAULT.aaveWithdrawLst(params.collateralInLst);

        VAULT.sendLst(address(this), params.collateralInLst);

        uint256 redemptionAmount = VAULT.LST().convertToAssets(params.collateralInLst);
        console.log("collateralInLST", params.collateralInLst);

        uint256 wethOut = convertLstToWeth(params.collateralInLst, params.convertLstToWethData);

        console.log("WETH out", wethOut);
        console.log("debtInETH", params.debtInEth);
        console.log("diff", wethOut - params.debtInEth);

        uint256 amountToRecipient = wethOut - params.debtInEth - flashLoanFee;

        console.log("amountToRecipient", amountToRecipient);
        console.log("redemptionAmount", redemptionAmount - params.debtInEth - flashLoanFee);

        // amountToRecipient 490,693_825_747_729_828_432_025
        // redemptionAmount  499,437_528_179_624_931_668_457

        // 157,743_246_614_722_991_068_698

        IERC20(address(VAULT.WETH())).safeTransfer(params.recipient, amountToRecipient);
    }

    function _getAmountOfWethToBorrow() internal view returns (uint256) {
        VaultSnapshot.Data memory aaveAccount = VAULT.getVaultSnapshot();
        uint256 targetHealthFactor = VAULT.targetHealthFactor();
        uint256 availableBorrowInEth = aaveAccount.availableBorrowsInEth();
        uint256 debtInEth = aaveAccount.wethDebtAmount;

        if (aaveAccount.healthFactor < targetHealthFactor || availableBorrowInEth == 0) {
            return 0;
        }

        uint256 borrowAmount = (availableBorrowInEth * 0.95e18) / 1e18;

        if (debtInEth > 0) {
            // We calculate the amount we'd need to borrow to reach the target health factor
            // considering we'd deposit that amount back into the pool as collateral
            uint256 targetAmount = ((aaveAccount.healthFactor - targetHealthFactor) * debtInEth)
                / (targetHealthFactor - aaveAccount.liquidationThresholdScaled18);

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
