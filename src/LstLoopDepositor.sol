// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LSTVault} from "./LSTVault.sol";
import {AaveAccount} from "./libraries/AaveAccount.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LstLoopDepositor {
    using AaveAccount for AaveAccount.Data;

    LSTVault public immutable vault;

    uint256 public constant MAX_LOOP_ITERATIONS = 10;

    constructor(LSTVault _vault) {
        vault = _vault;

        IERC20(address(vault.WETH())).approve(address(vault), type(uint256).max);
        IERC20(address(vault.LST())).approve(address(vault), type(uint256).max);
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

/* (uint256 collateralInBase, uint256 debtInBase,,,,,) = aavePool.getUserAccountData(address(this));
        IPriceOracle oracle = aavePool.ADDRESSES_PROVIDER().getPriceOracle();
        uint256 wSonicPrice = oracle.getAssetPrice(address(wSonic));
        uint256 stsPrice = oracle.getAssetPrice(address(stakedSonic));

        // Calculate proportional debt and collateral to unwind
        uint256 totalShares = totalSupply();

        uint256 debtToRepayInBase = (debtInBase * shares) / totalShares;
        uint256 collateralToWithdrawInBase = (collateralInBase * shares) / totalShares; */

/* for (uint256 i = 0; i < MAX_LOOP_ITERATIONS; i++) {
            if (debtToRepayInBase == 0) {
                break;
            }

            uint256 amountToWithdrawInBase = _getMaxAmountWithdrawableInBase(lstPrice);

            if (debtToRepayInBase < amountToWithdrawInBase) {
                amountToWithdrawInBase = debtToRepayInBase;
            } else {
                amountToWithdrawInBase = amountToWithdrawInBase * 0.99e18 / 1e18;
            }

            uint256 amountToWithdrawInLst = amountToWithdrawInBase * 1e18 / lstPrice;

            aavePool.withdraw(address(stakedSonic), amountToWithdrawInLst, address(this));
            uint256 sReceived = _convertStSToS(amountToWithdrawInLst);
            aavePool.repay(address(wSonic), sReceived, VARIABLE_INTEREST_RATE, address(this));

            debtToRepayInBase -= sReceived;
            collateralToWithdraw -= amountToWithdrawAsLst;
        } */

/* uint256 proportionalDebt = (data.debt * shares) / totalShares;

        uint256 assets = (data.collateral * shares) / totalShares;
        uint256 assetsAsLst = stakedSonic.convertToShares(assets);

        // Withdraw stS collateral from Aave
        aavePool.withdraw(address(stakedSonic), assetsAsLst, address(this));

        // Convert stS to S for debt repayment
        uint256 sReceived = _convertStSToS(assetsAsLst);

        if (sReceived < proportionalDebt) {
            revert("Not enough S received to repay debt");
        }

        aavePool.repay(address(asset()), proportionalDebt, VARIABLE_INTEREST_RATE, address(this));

        // Account for any slippage in the stS -> S conversion
        assets = assets - proportionalDebt + sReceived;

        uint256 remainingStS = stakedSonic.convertToShares(assets);

        if (remainingStS > 0) {
            aavePool.withdraw(address(stakedSonic), remainingStS, address(this));
            _convertStSToS(remainingStS);
        } */

//emit PositionUnwound(sReceived, stSToSell + remainingStS);
