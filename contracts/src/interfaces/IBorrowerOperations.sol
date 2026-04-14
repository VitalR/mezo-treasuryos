// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IBorrowerOperations
/// @notice TreasuryOS integration surface aligned to Mezo BorrowerOperations position lifecycle actions.
/// @dev `openTrove`, `adjustTrove`, and the convenience functions mirror Mezo docs and upstream CDP patterns.
interface IBorrowerOperations {
    /// @notice Returns the borrowing fee for a requested debt draw.
    /// @param _musdAmount Amount of MUSD debt principal to quote.
    function getBorrowingFee(uint256 _musdAmount) external view returns (uint256);

    /// @notice Opens a new Mezo position and borrows MUSD against posted BTC collateral.
    /// @param _musdAmount Amount of MUSD debt principal to draw.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint) external payable;

    /// @notice Adjusts an active Mezo position by changing collateral and/or debt principal.
    /// @param _collWithdrawal Amount of BTC collateral to withdraw.
    /// @param _debtChange Amount of MUSD debt principal to change.
    /// @param _isDebtIncrease Whether `_debtChange` increases debt principal.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;

    /// @notice Adds BTC collateral to an active position.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function addColl(address _upperHint, address _lowerHint) external payable;

    /// @notice Withdraws BTC collateral from an active position.
    /// @param _amount Amount of BTC collateral to withdraw.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function withdrawColl(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Draws additional MUSD debt principal from an active position.
    /// @param _amount Amount of MUSD debt principal to draw.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Repays MUSD debt principal against an active position.
    /// @param _amount Amount of MUSD debt principal to repay.
    /// @param _upperHint Upper insertion hint for the sorted trove list.
    /// @param _lowerHint Lower insertion hint for the sorted trove list.
    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Closes the active position.
    function closeTrove() external;
}
