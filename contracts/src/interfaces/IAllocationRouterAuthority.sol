// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IAllocationRouterAuthority
/// @notice Authorization surface exposed by allocation routers for Treasury Account handler checks.
interface IAllocationRouterAuthority {
    /// @notice Returns whether a handler is authorized by the router.
    /// @param _handler Handler address being checked.
    function isAuthorizedHandler(address _handler) external view returns (bool);
}
