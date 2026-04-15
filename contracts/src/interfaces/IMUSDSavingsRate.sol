// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IMUSDSavingsRate
/// @notice TreasuryOS integration surface for the Mezo MUSD Savings Rate vault.
interface IMUSDSavingsRate {
    /// @notice Deposits MUSD into the savings rate vault and mints sMUSD to the caller.
    /// @param _amount Amount of MUSD to deposit.
    function deposit(uint256 _amount) external;

    /// @notice Withdraws MUSD by burning sMUSD from the caller.
    /// @param _amount Amount of sMUSD principal to burn and withdraw.
    function withdraw(uint256 _amount) external;

    /// @notice Claims accumulated yield for the caller.
    /// @return amount Amount of MUSD yield claimed.
    function claimYield() external returns (uint256 amount);

    /// @notice Returns the yield token address, which is MUSD for this vault.
    function yieldToken() external view returns (address);

    /// @notice Returns the sMUSD balance of an account.
    /// @param _account Account to query.
    function balanceOf(address _account) external view returns (uint256);

    /// @notice Returns claimable MUSD yield for an account.
    /// @param _account Account to query.
    function claimableYield(address _account) external view returns (uint256);
}
