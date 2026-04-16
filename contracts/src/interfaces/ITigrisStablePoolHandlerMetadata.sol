// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ITigrisStablePoolHandlerMetadata
/// @notice Read-only metadata exposed by Tigris stable-pool handlers for reporting surfaces.
interface ITigrisStablePoolHandlerMetadata {
    /// @notice Returns the paired stable token combined with MUSD in the target pool.
    function pairedToken() external view returns (address);

    /// @notice Returns the Tigris router used by the handler.
    function router() external view returns (address);
}
