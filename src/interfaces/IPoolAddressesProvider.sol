// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPriceOracle} from "./IPriceOracle.sol";

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPriceOracle() external view returns (IPriceOracle);
}
