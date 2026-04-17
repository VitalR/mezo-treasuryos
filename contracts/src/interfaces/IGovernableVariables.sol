// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IGovernableVariables
/// @notice Minimal TreasuryOS view into Mezo governable variables.
interface IGovernableVariables {
    /// @notice Returns the active TroveManager contract address.
    function troveManager() external view returns (address);

    /// @notice Returns the active protocol price feed address.
    function priceFeed() external view returns (address);
}
