// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMUSDSavingsRate } from "../../src/interfaces/IMUSDSavingsRate.sol";
import { MockMUSDToken } from "./MockMUSDToken.sol";

contract MockMUSDSavingsRate is ERC20, IMUSDSavingsRate {
    using SafeERC20 for IERC20;

    MockMUSDToken public immutable musdToken;
    uint256 public yieldIndex;
    mapping(address account => uint256 amount) public claimableYield;
    mapping(address account => uint256 index) public supplyYieldIndex;

    constructor(MockMUSDToken _musdToken) ERC20("Mock sMUSD", "sMUSD") {
        musdToken = _musdToken;
    }

    function deposit(uint256 _amount) external {
        IERC20(address(musdToken)).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        IERC20(address(musdToken)).safeTransfer(msg.sender, _amount);
    }

    function claimYield() external returns (uint256 amount) {
        amount = claimableYield[msg.sender];
        if (amount > 0) {
            claimableYield[msg.sender] = 0;
            IERC20(address(musdToken)).safeTransfer(msg.sender, amount);
        }
    }

    function yieldToken() external view returns (address) {
        return address(musdToken);
    }

    function balanceOf(address _account) public view override(ERC20, IMUSDSavingsRate) returns (uint256) {
        return super.balanceOf(_account);
    }

    function addClaimableYield(address _account, uint256 _amount) external {
        claimableYield[_account] += _amount;
        musdToken.mint(address(this), _amount);
    }
}
