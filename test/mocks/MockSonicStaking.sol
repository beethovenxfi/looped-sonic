// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISonicStaking} from "../../src/interfaces/ISonicStaking.sol";

contract MockSonicStaking is ERC20 {
    uint256 public rate = 1e18; // 1:1 initially
    
    constructor() ERC20("Staked Sonic", "stS") {}
    
    function deposit() external payable returns (uint256 sharesAmount) {
        sharesAmount = convertToShares(msg.value);
        _mint(msg.sender, sharesAmount);
    }
    
    function undelegate(uint256, uint256 amountShares) external returns (uint256 withdrawId) {
        _burn(msg.sender, amountShares);
        return 1;
    }
    
    function withdraw(uint256, bool) external returns (uint256 amountWithdrawn) {
        return 1e18;
    }
    
    function convertToShares(uint256 assetAmount) public view returns (uint256) {
        return (assetAmount * 1e18) / rate;
    }
    
    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        return (sharesAmount * rate) / 1e18;
    }
    
    function getRate() external view returns (uint256) {
        return rate;
    }
    
    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getUserWithdraws(address, uint256, uint256, bool) 
        external 
        pure 
        returns (ISonicStaking.WithdrawRequest[] memory) 
    {
        return new ISonicStaking.WithdrawRequest[](0);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setRate(uint256 newRate) external {
        rate = newRate;
    }
}