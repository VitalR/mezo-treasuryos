// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";

/// @title SavingsVaultAdapter
/// @notice Routes governed MUSD allocation into the configured MUSDSavingsRate destination.
contract SavingsVaultAdapter {
    /// @notice Emitted when TreasuryOS routes idle MUSD into MUSDSavingsRate.
    event SavingsDepositRouted(address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares);

    /// @notice Emitted when TreasuryOS restores idle MUSD principal from MUSDSavingsRate.
    event SavingsWithdrawalRouted(
        address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares
    );
    /// @notice Emitted when TreasuryOS claims yield from MUSDSavingsRate back into idle treasury balance.
    event SavingsYieldClaimed(address indexed treasuryAccount, address indexed actor, uint256 amount);

    error InvalidSavingsVault(address savingsVault);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);

    IMUSDSavingsRate public immutable savingsVault;

    /// @param _savingsVault Savings destination used for governed allocation.
    constructor(IMUSDSavingsRate _savingsVault) {
        require(address(_savingsVault) != address(0), InvalidSavingsVault(address(_savingsVault)));

        savingsVault = _savingsVault;
    }

    /// @notice Allocates idle MUSD from a Treasury Account into the savings vault.
    /// @param _treasuryAccount Treasury Account providing the idle MUSD.
    /// @param _amount Amount of MUSD being allocated.
    /// @return shares Savings vault shares minted to the Treasury Account.
    function deposit(TreasuryAccount _treasuryAccount, uint256 _amount) external returns (uint256 shares) {
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_amount > 0, InvalidAmount(_amount));

        shares = _treasuryAccount.depositIntoSavingsRateFromAdapter(msg.sender, address(savingsVault), _amount);

        emit SavingsDepositRouted(address(_treasuryAccount), msg.sender, _amount, shares);
    }

    /// @notice Withdraws MUSD from the savings vault back into the Treasury Account idle balance.
    /// @param _treasuryAccount Treasury Account receiving restored idle MUSD.
    /// @param _amount Amount of MUSD being withdrawn.
    /// @return shares Savings vault shares burned for the withdrawal.
    function withdraw(TreasuryAccount _treasuryAccount, uint256 _amount) external returns (uint256 shares) {
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_amount > 0, InvalidAmount(_amount));

        shares = _treasuryAccount.withdrawFromSavingsRateFromAdapter(msg.sender, address(savingsVault), _amount);

        emit SavingsWithdrawalRouted(address(_treasuryAccount), msg.sender, _amount, shares);
    }

    /// @notice Claims MUSD yield from MUSDSavingsRate back into the Treasury Account idle balance.
    /// @param _treasuryAccount Treasury Account receiving the claimed yield.
    /// @return amount Amount of MUSD yield claimed.
    function claimYield(TreasuryAccount _treasuryAccount) external returns (uint256 amount) {
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));

        amount = _treasuryAccount.claimSavingsRateYieldFromAdapter(msg.sender, address(savingsVault));

        emit SavingsYieldClaimed(address(_treasuryAccount), msg.sender, amount);
    }
}
