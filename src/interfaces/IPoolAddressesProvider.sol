// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPriceOracle} from "./IPriceOracle.sol";
import {IAaveProtocolDataProvider} from "./IAaveProtocolDataProvider.sol";

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPriceOracle() external view returns (IPriceOracle);
    function getPoolDataProvider() external view returns (IAaveProtocolDataProvider);
}
