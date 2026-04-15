// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";
import { IAllocationRouterAuthority } from "../interfaces/IAllocationRouterAuthority.sol";

/// @title AllocationRouter
/// @notice TreasuryOS router that dispatches destination actions to registered sleeve handlers.
contract AllocationRouter is Ownable, IAllocationRouterAuthority {
    event HandlerRegistered(address indexed destination, address indexed handler);
    event HandlerRemoved(address indexed destination, address indexed handler);

    error InvalidDestination(address destination);
    error InvalidHandler(address handler);
    error MissingHandler(address destination);
    error HandlerDestinationMismatch(address destination, address handler, address reportedDestination);

    mapping(address destination => address handler) public handlers;
    mapping(address handler => uint256 count) private handlerReferenceCounts;

    constructor(address _owner) Ownable(_owner) { }

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

    function removeHandler(address _destination) external onlyOwner {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        handlerReferenceCounts[_handler] -= 1;
        delete handlers[_destination];

        emit HandlerRemoved(_destination, _handler);
    }

    function deposit(address _treasuryAccount, address _destination, uint256 _amount)
        external
        returns (uint256 result)
    {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        result = IAllocationHandler(_handler).deposit(_treasuryAccount, msg.sender, _amount);
    }

    function withdraw(address _treasuryAccount, address _destination, uint256 _amount)
        external
        returns (uint256 result)
    {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        result = IAllocationHandler(_handler).withdraw(_treasuryAccount, msg.sender, _amount);
    }

    function claimYield(address _treasuryAccount, address _destination) external returns (uint256 amount) {
        address _handler = handlers[_destination];
        require(_handler != address(0), MissingHandler(_destination));

        amount = IAllocationHandler(_handler).claimYield(_treasuryAccount, msg.sender);
    }

    function isAuthorizedHandler(address _handler) external view returns (bool) {
        return handlerReferenceCounts[_handler] > 0;
    }
}
