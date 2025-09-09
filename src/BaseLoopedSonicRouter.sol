// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LoopedSonicVault} from "./LoopedSonicVault.sol";
import {VaultSnapshot} from "./libraries/VaultSnapshot.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-origin/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "aave-v3-origin/interfaces/IPool.sol";

abstract contract BaseLoopedSonicRouter is IFlashLoanSimpleReceiver {
    using VaultSnapshot for VaultSnapshot.Data;
    using SafeERC20 for IERC20;

    error NotVault();
    error NotEnoughLst();
    error NotAavePool();
    error BadInitiator();
    error AmountOutBelowMin();

    LoopedSonicVault public immutable VAULT;

    uint256 public constant MAX_LOOP_ITERATIONS = 20;

    constructor(LoopedSonicVault _vault) {
        VAULT = _vault;

        IERC20(address(VAULT.WETH())).approve(address(VAULT), type(uint256).max);
        IERC20(address(VAULT.LST())).approve(address(VAULT), type(uint256).max);
    }

    function convertWethSessionBalanceToLstSessionBalance(uint256 wethAmount) internal virtual returns (uint256);
    function convertLstToWeth(uint256 lstCollateralAmount, bytes memory data) internal virtual returns (uint256);

    modifier onlyVault() {
        require(msg.sender == address(VAULT), NotVault());
        _;
    }

    function deposit() external payable {
        IWETH(address(VAULT.WETH())).deposit{value: msg.value}();

        VAULT.deposit(msg.sender, abi.encodeCall(BaseLoopedSonicRouter.depositCallback, (msg.value)));
    }

    function depositCallback(uint256 initialAssets) external onlyVault {
        uint256 currentAssets = initialAssets;
        uint256 totalCollateral = 0;

        VAULT.pullWeth(initialAssets);

        for (uint256 i = 0; i < MAX_LOOP_ITERATIONS && currentAssets > 0; i++) {
            uint256 minLstAmount = VAULT.LST().convertToShares(currentAssets);
            uint256 lstAmount = convertWethSessionBalanceToLstSessionBalance(currentAssets);

            // The router implementation must ensure that the amount of LST received is at least the amount of
            // shares that would be received if the WETH was staked
            require(lstAmount >= minLstAmount, NotEnoughLst());

            VAULT.aaveSupplyLst(lstAmount);

            totalCollateral += lstAmount;

            uint256 borrowAmount = VAULT.getBorrowAmountForLoopInEth();

            if (borrowAmount < VAULT.MIN_LST_DEPOSIT()) {
                break;
            }

            VAULT.aaveBorrowWeth(borrowAmount);
            currentAssets = borrowAmount;
        }
    }

    struct WithdrawParams {
        address recipient;
        uint256 amountShares;
        uint256 minWethAmountOut;
        uint256 collateralInLst;
        uint256 debtInEth;
        bytes convertLstToWethData;
    }

    /**
     * @notice burns shares, repay debt and return remaining collateral to the caller
     * @param amountShares The amount of shares to burn
     * @param minWethAmountOut The minimum amount of WETH to receive
     * @param convertLstToWethData abi encoded data used by the router implementation to convert the LST to WETH
     * @dev This path will only work for small withdrawals relative to the vault size. If the number of shares is too
     * large the withdraw from aave will bring the health factor below 1.0 and revert.
     */
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

        VAULT.withdraw(amountShares, abi.encodeCall(BaseLoopedSonicRouter.withdrawCallback, (params)));
    }

    function withdrawCallback(WithdrawParams memory params) external onlyVault {
        // This will revert if the withdraw would bring the health factor below 1.0.
        // For large withdrawals, use withdrawWithFlashLoan.
        VAULT.aaveWithdrawLst(params.collateralInLst);

        VAULT.sendLst(address(this), params.collateralInLst);

        uint256 wethOut = convertLstToWeth(params.collateralInLst, params.convertLstToWethData);

        VAULT.pullWeth(params.debtInEth);

        VAULT.aaveRepayWeth(params.debtInEth);

        uint256 amountToRecipient = wethOut - params.debtInEth;

        require(amountToRecipient >= params.minWethAmountOut, AmountOutBelowMin());

        IERC20(address(VAULT.WETH())).safeTransfer(params.recipient, amountToRecipient);
    }

    /**
     * @notice burns shares, repay debt and return remaining collateral to the caller
     * @param amountShares The amount of shares to burn
     * @param minWethAmountOut The minimum amount of WETH to receive
     * @param convertLstToWethData abi encoded data used by the router implementation to convert the LST to WETH
     * @dev This path takes a flash loan from Aave, it can facilitate larger withdrawals, but is subject to the 5 BPS
     * fee.
     */
    function withdrawWithFlashLoan(uint256 amountShares, uint256 minWethAmountOut, bytes memory convertLstToWethData)
        external
    {
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

        // The aave flash loan will callback into this contract, calling the executeOperation function.
        VAULT.AAVE_POOL().flashLoanSimple(address(this), address(VAULT.WETH()), params.debtInEth, abi.encode(params), 0);
    }

    function executeOperation(
        address asset,
        uint256 flashLoanAmount,
        uint256 flashLoanFee,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(VAULT.AAVE_POOL()), NotAavePool());
        require(initiator == address(this), BadInitiator());

        WithdrawParams memory withdrawParams = abi.decode(params, (WithdrawParams));

        VAULT.withdraw(
            withdrawParams.amountShares,
            abi.encodeCall(BaseLoopedSonicRouter.withdrawWithFlashLoanCallback, (withdrawParams, flashLoanFee))
        );

        // Allow aave to pull the funds to pay back the flashloan + fee
        IERC20(asset).approve(address(VAULT.AAVE_POOL()), flashLoanAmount + flashLoanFee);

        return true;
    }

    function withdrawWithFlashLoanCallback(WithdrawParams memory params, uint256 flashLoanFee) external onlyVault {
        VAULT.pullWeth(params.debtInEth);

        VAULT.aaveRepayWeth(params.debtInEth);

        VAULT.aaveWithdrawLst(params.collateralInLst);

        VAULT.sendLst(address(this), params.collateralInLst);

        uint256 wethOut = convertLstToWeth(params.collateralInLst, params.convertLstToWethData);

        uint256 amountToRecipient = wethOut - params.debtInEth - flashLoanFee;

        require(amountToRecipient >= params.minWethAmountOut, AmountOutBelowMin());

        IERC20(address(VAULT.WETH())).safeTransfer(params.recipient, amountToRecipient);
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return VAULT.AAVE_POOL().ADDRESSES_PROVIDER();
    }

    function POOL() external view returns (IPool) {
        return VAULT.AAVE_POOL();
    }
}
