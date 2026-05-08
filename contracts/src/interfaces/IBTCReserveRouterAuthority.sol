// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IBTCReserveRouterAuthority
/// @notice Authorization surface exposed by BTC reserve routers for Treasury Account handler checks.
interface IBTCReserveRouterAuthority {
    /// @notice Returns whether a BTC sleeve handler is authorized by the router.
    /// @param _handler Handler address being checked.
    function isAuthorizedBTCHandler(address _handler) external view returns (bool);
}
