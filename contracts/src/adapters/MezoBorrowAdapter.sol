// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IMezoBorrowOperations } from "../interfaces/IMezoBorrowOperations.sol";

/// @title MezoBorrowAdapter
/// @notice Wraps Mezo-native BTC-backed borrow origination for TreasuryOS Treasury Accounts.
contract MezoBorrowAdapter {
    /// @notice Emitted when a Mezo borrow flow is originated through TreasuryOS.
    event BorrowOriginated(
        address indexed treasuryAccount,
        address indexed actor,
        uint256 btcAmount,
        uint256 musdAmount,
        uint256 positionId
    );

    error InvalidBorrowAmount(uint256 amount);
    error InvalidBorrowOperations(address borrowOperations);
    error InvalidCollateralAmount(uint256 amount);
    error InvalidTreasuryAccount(address treasuryAccount);

    IMezoBorrowOperations public immutable borrowOperations;

    /// @param _borrowOperations Mezo-native borrow operations contract used for origination.
    constructor(IMezoBorrowOperations _borrowOperations) {
        require(address(_borrowOperations) != address(0), InvalidBorrowOperations(address(_borrowOperations)));

        borrowOperations = _borrowOperations;
    }

    /// @notice Originates a BTC-backed borrow flow into a Treasury Account.
    /// @param _treasuryAccount Treasury Account receiving the borrowed MUSD.
    /// @param _btcAmount BTC collateral amount posted into the Mezo borrow flow.
    /// @param _musdAmount MUSD amount to borrow.
    /// @return positionId Mezo borrow position identifier.
    function originateBorrow(TreasuryAccount _treasuryAccount, uint256 _btcAmount, uint256 _musdAmount)
        external
        returns (uint256 positionId)
    {
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_btcAmount > 0, InvalidCollateralAmount(_btcAmount));
        require(_musdAmount > 0, InvalidBorrowAmount(_musdAmount));

        positionId = borrowOperations.depositAndBorrow(
            address(_treasuryAccount), _btcAmount, _musdAmount, address(_treasuryAccount)
        );

        _treasuryAccount.recordBorrowFromAdapter(msg.sender, _musdAmount);

        emit BorrowOriginated(address(_treasuryAccount), msg.sender, _btcAmount, _musdAmount, positionId);
    }
}
