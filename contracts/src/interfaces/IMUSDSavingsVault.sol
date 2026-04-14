// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMUSDSavingsVault
/// @notice Minimal interface for the Mezo-native MUSD savings destination used by TreasuryOS.
interface IMUSDSavingsVault {
    /// @notice Deposits MUSD into the savings vault.
    /// @param _assets Amount of MUSD being deposited.
    /// @param _receiver Receiver credited in the destination.
    /// @return shares Destination shares minted for the deposit.
    function deposit(uint256 _assets, address _receiver) external returns (uint256 shares);

    /// @notice Withdraws MUSD from the savings vault.
    /// @param _assets Amount of MUSD being withdrawn.
    /// @param _receiver Recipient of the withdrawn MUSD.
    /// @param _owner Owner whose destination position is reduced.
    /// @return shares Destination shares burned for the withdrawal.
    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256 shares);
}
