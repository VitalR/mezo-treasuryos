// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IAllocationRouterView
/// @notice Read-only surface used by Treasury Accounts to inspect registered destination handlers.
interface IAllocationRouterView {
    /// @notice Returns the handler registered for a destination.
    /// @param _destination Destination being queried.
    function handlers(address _destination) external view returns (address);
}
