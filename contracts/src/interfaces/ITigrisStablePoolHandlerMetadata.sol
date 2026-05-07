// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ITigrisStablePoolHandlerMetadata
/// @notice Read-only metadata exposed by Tigris pool handlers for reporting surfaces.
interface ITigrisStablePoolHandlerMetadata {
    /// @notice Returns the paired token combined with MUSD in the target pool.
    function pairedToken() external view returns (address);

    /// @notice Returns the Tigris router used by the handler.
    function router() external view returns (address);

    /// @notice Returns the Tigris pool factory used for routes and liquidity actions.
    function poolFactory() external view returns (address);

    /// @notice Returns whether the target Tigris pool is stable.
    function poolStable() external view returns (bool);

    /// @notice Returns the maximum accepted execution slippage in basis points.
    function maxSlippageBps() external view returns (uint256);
}
