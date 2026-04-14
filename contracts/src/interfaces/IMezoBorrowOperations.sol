// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMezoBorrowOperations
/// @notice Minimal interface for Mezo-native BTC-backed borrow origination used by TreasuryOS.
interface IMezoBorrowOperations {
    /// @notice Routes BTC collateral into Mezo and borrows MUSD into a recipient treasury boundary.
    /// @param _onBehalfOf Treasury boundary or borrower-of-record in the Mezo flow.
    /// @param _btcAmount Amount of BTC collateral being posted.
    /// @param _musdAmount Amount of MUSD being borrowed.
    /// @param _recipient Recipient of the borrowed MUSD.
    /// @return positionId Mezo borrow position identifier.
    function depositAndBorrow(address _onBehalfOf, uint256 _btcAmount, uint256 _musdAmount, address _recipient)
        external
        returns (uint256 positionId);
}
