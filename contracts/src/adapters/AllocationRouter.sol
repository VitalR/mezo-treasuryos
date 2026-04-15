// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";
import { IAllocationRouterAuthority } from "../interfaces/IAllocationRouterAuthority.sol";

/// @title AllocationRouter
/// @notice TreasuryOS router that dispatches destination actions to registered sleeve handlers.
/// @dev The Treasury Account trusts one router address. The router, in turn, maps many destinations to
///      many handler contracts so TreasuryOS can support multiple sleeves without changing Treasury Account custody.
contract AllocationRouter is Ownable2Step, IAllocationRouterAuthority {
    /// @notice Emitted when a destination is assigned to a handler.
    /// @param destination Destination governed by the handler.
    /// @param handler Handler registered for the destination.
    event HandlerRegistered(address indexed destination, address indexed handler);
    /// @notice Emitted when a destination handler is removed.
    /// @param destination Destination that no longer has a registered handler.
    /// @param handler Handler that was removed.
    event HandlerRemoved(address indexed destination, address indexed handler);

    /// @notice Reverts when the destination is zero.
    /// @param destination Invalid destination address.
    error InvalidDestination(address destination);
    /// @notice Reverts when the handler is zero.
    /// @param handler Invalid handler address.
    error InvalidHandler(address handler);
    /// @notice Reverts when no handler has been registered for the destination.
    /// @param destination Destination that was requested.
    error MissingHandler(address destination);
    /// @notice Reverts when a handler reports a different destination than the one being registered.
    /// @param destination Destination being configured on the router.
    /// @param handler Handler being registered.
    /// @param reportedDestination Destination returned by `handler.destination()`.
    error HandlerDestinationMismatch(address destination, address handler, address reportedDestination);

    /// @notice Maps a treasury destination to the handler that can operate it.
    mapping(address destination => address handler) public handlers;
    /// @notice Tracks how many destinations reference a given handler so Treasury Accounts can authorize handlers
    /// safely.
    mapping(address handler => uint256 count) private handlerReferenceCounts;

    /// @param _owner Initial owner responsible for router administration.
    constructor(address _owner) Ownable(_owner) { }

    /// @notice Registers or replaces the handler for a destination.
    /// @param _destination Destination whose handler is being configured.
    /// @param _handler Handler that will manage the destination.
    function setHandler(address _destination, IAllocationHandler _handler) external onlyOwner {
        require(_destination != address(0), InvalidDestination(_destination));
        require(address(_handler) != address(0), InvalidHandler(address(_handler)));

        address _reportedDestination = _handler.destination();
        require(
            _reportedDestination == _destination,
            HandlerDestinationMismatch(_destination, address(_handler), _reportedDestination)
        );

        address _previousHandler = handlers[_destination];
        if (_previousHandler != address(0)) {
            handlerReferenceCounts[_previousHandler] -= 1;
        }

        handlers[_destination] = address(_handler);
        handlerReferenceCounts[address(_handler)] += 1;

        emit HandlerRegistered(_destination, address(_handler));
    }

    /// @notice Removes the handler registered for a destination.
    /// @param _destination Destination whose handler should be removed.
    function removeHandler(address _destination) external onlyOwner {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        handlerReferenceCounts[_handler] -= 1;
        delete handlers[_destination];

        emit HandlerRemoved(_destination, _handler);
    }

    /// @notice Dispatches a deposit request to the handler registered for a destination.
    /// @param _treasuryAccount Treasury Account providing funds and receiving downstream position tokens.
    /// @param _destination Destination being entered.
    /// @param _amount Amount requested by the treasury actor.
    /// @return result Destination-specific result such as shares or liquidity minted.
    function deposit(address _treasuryAccount, address _destination, uint256 _amount)
        external
        returns (uint256 result)
    {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        result = IAllocationHandler(_handler).deposit(_treasuryAccount, msg.sender, _amount);
    }

    /// @notice Dispatches a withdrawal request to the handler registered for a destination.
    /// @param _treasuryAccount Treasury Account receiving the withdrawal proceeds.
    /// @param _destination Destination being exited.
    /// @param _amount Amount requested by the treasury actor.
    /// @return result Destination-specific result such as shares or liquidity burned.
    function withdraw(address _treasuryAccount, address _destination, uint256 _amount)
        external
        returns (uint256 result)
    {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        result = IAllocationHandler(_handler).withdraw(_treasuryAccount, msg.sender, _amount);
    }

    /// @notice Dispatches a yield-claim request to the handler registered for a destination.
    /// @param _treasuryAccount Treasury Account receiving the claimed yield.
    /// @param _destination Destination paying the yield.
    /// @return amount Amount of yield returned to the Treasury Account.
    function claimYield(address _treasuryAccount, address _destination) external returns (uint256 amount) {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        amount = IAllocationHandler(_handler).claimYield(_treasuryAccount, msg.sender);
    }

    /// @inheritdoc IAllocationRouterAuthority
    function isAuthorizedHandler(address _handler) external view returns (bool) {
        return handlerReferenceCounts[_handler] > 0;
    }
}
