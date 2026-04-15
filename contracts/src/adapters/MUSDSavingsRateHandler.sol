// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";
import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";

/// @title MUSDSavingsRateHandler
/// @notice Single-sleeve allocation handler that routes governed MUSD into the configured MUSDSavingsRate destination.
contract MUSDSavingsRateHandler is IAllocationHandler {
    /// @notice Emitted when TreasuryOS routes idle MUSD into MUSDSavingsRate.
    event SavingsDepositRouted(address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares);

    /// @notice Emitted when TreasuryOS restores idle MUSD principal from MUSDSavingsRate.
    event SavingsWithdrawalRouted(
        address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares
    );
    /// @notice Emitted when TreasuryOS claims yield from MUSDSavingsRate back into idle treasury balance.
    event SavingsYieldClaimed(address indexed treasuryAccount, address indexed actor, uint256 amount);

    error InvalidSavingsVault(address savingsVault);
    error InvalidAllocationRouter(address allocationRouter);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);
    error UnauthorizedCaller(address caller);

    IMUSDSavingsRate public immutable savingsVault;
    address public immutable allocationRouter;

    /// @param _savingsVault Savings destination used for governed allocation.
    /// @param _allocationRouter Router allowed to dispatch calls to this handler.
    constructor(IMUSDSavingsRate _savingsVault, address _allocationRouter) {
        require(address(_savingsVault) != address(0), InvalidSavingsVault(address(_savingsVault)));
        require(_allocationRouter != address(0), InvalidAllocationRouter(_allocationRouter));

        savingsVault = _savingsVault;
        allocationRouter = _allocationRouter;
    }

    /// @inheritdoc IAllocationHandler
    function destination() external view returns (address) {
        return address(savingsVault);
    }

    /// @inheritdoc IAllocationHandler
    function deposit(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 shares) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        shares = TreasuryAccount(payable(_treasuryAccount))
            .depositIntoSavingsRateFromAdapter(_actor, address(savingsVault), _amount);

        emit SavingsDepositRouted(_treasuryAccount, _actor, _amount, shares);
    }

    /// @inheritdoc IAllocationHandler
    function withdraw(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 shares) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        shares = TreasuryAccount(payable(_treasuryAccount))
            .withdrawFromSavingsRateFromAdapter(_actor, address(savingsVault), _amount);

        emit SavingsWithdrawalRouted(_treasuryAccount, _actor, _amount, shares);
    }

    /// @inheritdoc IAllocationHandler
    function claimYield(address _treasuryAccount, address _actor) external returns (uint256 amount) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));

        amount =
            TreasuryAccount(payable(_treasuryAccount)).claimSavingsRateYieldFromAdapter(_actor, address(savingsVault));

        emit SavingsYieldClaimed(_treasuryAccount, _actor, amount);
    }
}
