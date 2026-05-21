// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ITroveManager
/// @notice Minimal TreasuryOS view into Mezo TroveManager state.
interface ITroveManager {
    /// @notice Returns the protocol gas compensation applied to trove debt.
    function MUSD_GAS_COMPENSATION() external view returns (uint256);

    /// @notice Returns the entire collateral and debt for a borrower, including pending updates.
    /// @dev The Mezo testnet implementation uses this selector name but returns collateral first, debt second.
    /// @param _borrower Borrower address to query.
    function getEntireDebtAndColl(address _borrower) external view returns (uint256 coll, uint256 debt);
}
