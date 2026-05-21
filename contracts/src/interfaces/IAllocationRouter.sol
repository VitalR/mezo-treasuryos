// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IAllocationRouter
/// @notice Minimal TreasuryOS router interface used by Treasury Accounts for workflow-scoped sleeve actions.
interface IAllocationRouter {
    /// @notice Dispatches a deposit request on behalf of a Treasury Account while preserving the treasury actor.
    /// @param _treasuryAccount Treasury Account requesting the sleeve deposit.
    /// @param _actor Treasury actor on whose behalf the deposit is being executed.
    /// @param _destination Destination being entered.
    /// @param _amount Amount requested for deposit.
    /// @return result Destination-specific result such as minted shares or liquidity.
    function depositFor(address _treasuryAccount, address _actor, address _destination, uint256 _amount)
        external
        returns (uint256 result);

    /// @notice Dispatches a withdrawal request on behalf of a Treasury Account while preserving the treasury actor.
    /// @param _treasuryAccount Treasury Account requesting the sleeve unwind.
    /// @param _actor Treasury actor on whose behalf the withdrawal is being executed.
    /// @param _destination Destination being unwound.
    /// @param _amount Amount requested for withdrawal.
    /// @return result Destination-specific result such as burned shares or liquidity.
    function withdrawFor(address _treasuryAccount, address _actor, address _destination, uint256 _amount)
        external
        returns (uint256 result);
}
