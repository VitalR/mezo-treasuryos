// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";

/// @title DemoMUSDSavingsRate
/// @notice Demo-grade savings sleeve that mimics sMUSD principal and yield behavior with owner-funded yield injections.
contract DemoMUSDSavingsRate is ERC20, Ownable, ReentrancyGuard, IMUSDSavingsRate {
    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event YieldClaimed(address indexed user, uint256 amount);
    event YieldFunded(address indexed funder, uint256 amount);

    error InsufficientBalance();
    error NoShares();
    error ZeroAddress();
    error ZeroAmount();

    IERC20 public immutable musdToken;
    uint256 public yieldIndex;
    uint256 public pendingYield;
    uint256 public lastYieldFundedAt;
    uint256 public lastYieldFundedAmount;

    mapping(address account => uint256 amount) public claimableYield;
    mapping(address account => uint256 index) public supplyYieldIndex;

    constructor(address _owner, IERC20 _musdToken) ERC20("Demo MUSD Savings Rate", "sMUSD") Ownable(_owner) {
        require(address(_musdToken) != address(0), ZeroAddress());

        musdToken = _musdToken;
    }

    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, ZeroAmount());

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, ZeroAmount());
        require(balanceOf(msg.sender) >= _amount, InsufficientBalance());

        _claimYield(msg.sender);
        _burn(msg.sender, _amount);
        musdToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function claimYield() external nonReentrant returns (uint256 amount) {
        amount = _claimYield(msg.sender);
    }

    function yieldToken() external view returns (address) {
        return address(musdToken);
    }

    function balanceOf(address _account) public view override(ERC20, IMUSDSavingsRate) returns (uint256) {
        return super.balanceOf(_account);
    }

    /// @notice Funds demo yield using real MUSD already held by the owner and distributes it pro-rata to sMUSD holders.
    /// @param _amount Amount of MUSD yield to transfer into the vault and distribute.
    function fundYield(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount > 0, ZeroAmount());

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        _receiveYield(_amount);
        lastYieldFundedAt = block.timestamp;
        lastYieldFundedAmount = _amount;

        emit YieldFunded(msg.sender, _amount);
    }

    function _claimYield(address _account) internal returns (uint256 amount) {
        require(balanceOf(_account) > 0, NoShares());

        _updateYieldFor(_account);

        amount = claimableYield[_account];
        if (amount > 0) {
            claimableYield[_account] = 0;
            musdToken.safeTransfer(_account, amount);
            emit YieldClaimed(_account, amount);
        }
    }

    function _receiveYield(uint256 _amount) internal {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            uint256 _distributedYield = _amount + pendingYield;
            pendingYield = 0;

            uint256 _ratio = (_distributedYield * 1e18) / _totalSupply;
            if (_ratio > 0) {
                yieldIndex += _ratio;
            }
            return;
        }

        pendingYield += _amount;
    }

    function _updateYieldFor(address _account) internal {
        uint256 _supplied = balanceOf(_account);
        uint256 _currentYieldIndex = yieldIndex;
        uint256 _accountYieldIndex = supplyYieldIndex[_account];

        supplyYieldIndex[_account] = _currentYieldIndex;

        if (_supplied == 0) {
            return;
        }

        uint256 _delta = _currentYieldIndex - _accountYieldIndex;
        if (_delta > 0) {
            claimableYield[_account] += (_supplied * _delta) / 1e18;
        }
    }

    function _update(address _from, address _to, uint256 _value) internal override {
        _updateYieldFor(_from);
        _updateYieldFor(_to);
        super._update(_from, _to, _value);
    }
}
