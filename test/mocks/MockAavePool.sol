// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAavePool} from "../../src/interfaces/IAavePool.sol";
import {IPoolAddressesProvider} from "../../src/interfaces/IPoolAddressesProvider.sol";

contract MockAavePool is IAavePool {
    mapping(address => uint256) public supplies;
    mapping(address => uint256) public borrows;

    function supply(address asset, uint256 amount, address, uint16) external override {
        supplies[asset] += amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address) external override {
        borrows[asset] += amount;
    }

    function repay(address asset, uint256 amount, uint256, address) external override returns (uint256) {
        if (amount == type(uint256).max) {
            amount = borrows[asset];
        }
        borrows[asset] -= amount;
        return amount;
    }

    function withdraw(address asset, uint256 amount, address) external override returns (uint256) {
        if (amount == type(uint256).max) {
            amount = supplies[asset];
        }
        supplies[asset] -= amount;
        return amount;
    }

    function getUserAccountData(address)
        external
        view
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        totalCollateralBase = 1000e18;
        totalDebtBase = 500e18;
        availableBorrowsBase = 400e18;
        currentLiquidationThreshold = 8000;
        ltv = 7500;
        healthFactor = 2e18;
    }

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external override {
        // TODO: implement
    }

    function setUserEMode(uint8 categoryId) external override {
        // TODO: implement
    }

    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(address(0));
    }

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external override {}
}
