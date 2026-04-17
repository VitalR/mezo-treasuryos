// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IPriceFeed
/// @notice Minimal TreasuryOS view into the Mezo collateral price feed.
interface IPriceFeed {
    /// @notice Returns the latest collateral price used for treasury health calculations.
    /// @dev The returned value is assumed to use 18 decimals of precision.
    /// @return price Latest collateral price scaled by 1e18.
    function fetchPrice() external view returns (uint256 price);
}
