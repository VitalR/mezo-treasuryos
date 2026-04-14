// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IMUSDSavingsVault } from "../interfaces/IMUSDSavingsVault.sol";

/// @title SavingsVaultAdapter
/// @notice Routes governed MUSD allocation into the configured savings destination.
contract SavingsVaultAdapter {
    /// @notice Emitted when TreasuryOS routes idle MUSD into the savings vault.
    event SavingsDepositRouted(address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares);

    /// @notice Emitted when TreasuryOS restores idle MUSD from the savings vault.
    event SavingsWithdrawalRouted(
        address indexed treasuryAccount, address indexed actor, uint256 amount, uint256 shares
    );

    error InvalidSavingsVault(address savingsVault);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);

    IMUSDSavingsVault public immutable savingsVault;

    /// @param _savingsVault Savings destination used for governed allocation.
    constructor(IMUSDSavingsVault _savingsVault) {
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

        _treasuryAccount.allocateFromAdapter(msg.sender, address(savingsVault), _amount);
        shares = savingsVault.deposit(_amount, address(_treasuryAccount));

        emit SavingsDepositRouted(address(_treasuryAccount), msg.sender, _amount, shares);
    }

    /// @notice Withdraws MUSD from the savings vault back into the Treasury Account idle balance.
    /// @param _treasuryAccount Treasury Account receiving restored idle MUSD.
    /// @param _amount Amount of MUSD being withdrawn.
    /// @return shares Savings vault shares burned for the withdrawal.
    function withdraw(TreasuryAccount _treasuryAccount, uint256 _amount) external returns (uint256 shares) {
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_amount > 0, InvalidAmount(_amount));

        shares = savingsVault.withdraw(_amount, address(_treasuryAccount), address(_treasuryAccount));
        _treasuryAccount.withdrawFromAdapter(msg.sender, address(savingsVault), _amount);

        emit SavingsWithdrawalRouted(address(_treasuryAccount), msg.sender, _amount, shares);
    }
}
