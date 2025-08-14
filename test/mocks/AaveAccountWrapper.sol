// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AaveAccount} from "../../src/libraries/AaveAccount.sol";
import {IAavePool} from "../../src/interfaces/IAavePool.sol";

contract AaveAccountWrapper {
    using AaveAccount for AaveAccount.Data;

    AaveAccount.Data public data;

    constructor(AaveAccount.Data memory _data) {
        data = _data;
    }

    function initialize(IAavePool aavePool, address vault, uint256 ethPrice, uint256 lstPrice) external {
        AaveAccount.Data memory newData;
        newData.initialize(aavePool, vault, ethPrice, lstPrice);

        data = newData;
    }

    function netAssetValueBase() external view returns (uint256) {
        return data.netAssetValueBase();
    }

    function netAssetValueInEth() external view returns (uint256) {
        return data.netAssetValueInEth();
    }

    function proportionalCollateralBase(uint256 shares, uint256 totalSupply) external view returns (uint256) {
        return data.proportionalCollateralBase(shares, totalSupply);
    }

    function proportionalDebtBase(uint256 shares, uint256 totalSupply) external view returns (uint256) {
        return data.proportionalDebtBase(shares, totalSupply);
    }

    function proportionalCollateralInLst(uint256 shares, uint256 totalSupply) external view returns (uint256) {
        return data.proportionalCollateralInLst(shares, totalSupply);
    }

    function proportionalDebtInEth(uint256 shares, uint256 totalSupply) external view returns (uint256) {
        return data.proportionalDebtInEth(shares, totalSupply);
    }

    function baseToEth(uint256 amount) external view returns (uint256) {
        return data.baseToEth(amount);
    }

    function baseToLst(uint256 amount) external view returns (uint256) {
        return data.baseToLst(amount);
    }

    function liquidationThresholdScaled18() external view returns (uint256) {
        return data.liquidationThresholdScaled18();
    }

    function updateData(AaveAccount.Data memory _data) external {
        data = _data;
    }

    function getData() external view returns (AaveAccount.Data memory) {
        return data;
    }
}
