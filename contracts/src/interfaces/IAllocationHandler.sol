// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IAllocationHandler
/// @notice Common handler interface used by TreasuryOS allocation routers to manage destination-specific sleeves.
interface IAllocationHandler {
    /// @notice Returns the destination managed by this handler.
    function destination() external view returns (address);

    /// @notice Routes a treasury deposit into the handler's destination.
    /// @param _treasuryAccount Treasury Account providing the idle balance.
    /// @param _actor Treasury actor initiating the routed action.
    /// @param _amount Amount being deposited.
    /// @return result Destination-specific deposit result, such as shares minted.
    function deposit(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 result);

    /// @notice Routes a treasury withdrawal from the handler's destination.
    /// @param _treasuryAccount Treasury Account receiving restored idle balance.
    /// @param _actor Treasury actor initiating the routed action.
    /// @param _amount Amount being withdrawn.
    /// @return result Destination-specific withdrawal result, such as shares burned.
    function withdraw(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 result);

    /// @notice Routes a treasury yield claim from the handler's destination.
    /// @param _treasuryAccount Treasury Account receiving claimed yield.
    /// @param _actor Treasury actor initiating the routed action.
    /// @return amount Amount of yield claimed back to the Treasury Account.
    function claimYield(address _treasuryAccount, address _actor) external returns (uint256 amount);
}
