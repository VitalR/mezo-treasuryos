// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBTCReserveHandler } from "../interfaces/IBTCReserveHandler.sol";
import { IBTCReserveRouterAuthority } from "../interfaces/IBTCReserveRouterAuthority.sol";

/// @title BTCReserveRouter
/// @notice Separate router for guarded BTC-denominated sleeve execution.
/// @dev This router is intentionally distinct from `AllocationRouter` so BTC-principal actions do not share MUSD
///      buffer accounting, MUSD sleeve caps, or operator-level automation paths.
contract BTCReserveRouter is Ownable2Step, IBTCReserveRouterAuthority {
    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when a BTC sleeve is assigned to a handler.
    /// @param sleeve BTC sleeve destination governed by the handler.
    /// @param handler Handler registered for the sleeve.
    event BTCHandlerRegistered(address indexed sleeve, address indexed handler);
    /// @notice Emitted when a BTC sleeve handler is removed.
    /// @param sleeve BTC sleeve that no longer has a registered handler.
    /// @param handler Handler that was removed.
    event BTCHandlerRemoved(address indexed sleeve, address indexed handler);

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Reverts when the BTC sleeve address is zero.
    /// @param sleeve Invalid sleeve address.
    error InvalidBTCSleeve(address sleeve);
    /// @notice Reverts when the BTC handler address is zero.
    /// @param handler Invalid handler address.
    error InvalidBTCHandler(address handler);
    /// @notice Reverts when no handler has been registered for a sleeve.
    /// @param sleeve Sleeve that was requested.
    error MissingBTCHandler(address sleeve);
    /// @notice Reverts when a handler reports a different destination than the one being registered.
    /// @param sleeve Sleeve being configured on the router.
    /// @param handler Handler being registered.
    /// @param reportedDestination Destination returned by `handler.destination()`.
    error BTCHandlerDestinationMismatch(address sleeve, address handler, address reportedDestination);

    // =============================================================
    // Storage
    // =============================================================

    /// @notice Maps a BTC sleeve destination to its execution handler.
    mapping(address sleeve => address handler) public handlers;
    /// @notice Tracks how many sleeves reference a handler so Treasury Accounts can authorize handlers safely.
    mapping(address handler => uint256 count) private handlerReferenceCounts;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _owner Initial owner responsible for BTC router administration.
    constructor(address _owner) Ownable(_owner) { }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Registers or replaces the handler for a BTC sleeve.
    /// @param _sleeve BTC sleeve whose handler is being configured.
    /// @param _handler Handler that will manage the sleeve.
    function setHandler(address _sleeve, IBTCReserveHandler _handler) external onlyOwner {
        require(_sleeve != address(0), InvalidBTCSleeve(_sleeve));
        require(address(_handler) != address(0), InvalidBTCHandler(address(_handler)));

        address _reportedDestination = _handler.destination();
        require(
            _reportedDestination == _sleeve,
            BTCHandlerDestinationMismatch(_sleeve, address(_handler), _reportedDestination)
        );

        address _previousHandler = handlers[_sleeve];
        if (_previousHandler != address(0)) {
            handlerReferenceCounts[_previousHandler] -= 1;
        }

        handlers[_sleeve] = address(_handler);
        handlerReferenceCounts[address(_handler)] += 1;

        emit BTCHandlerRegistered(_sleeve, address(_handler));
    }

    /// @notice Removes the handler registered for a BTC sleeve.
    /// @param _sleeve BTC sleeve whose handler should be removed.
    function removeHandler(address _sleeve) external onlyOwner {
        address _handler = handlers[_sleeve];
        require(_handler != address(0), MissingBTCHandler(_sleeve));

        handlerReferenceCounts[_handler] -= 1;
        delete handlers[_sleeve];

        emit BTCHandlerRemoved(_sleeve, _handler);
    }

    /// @notice Dispatches a guarded BTC sleeve deposit request to the registered handler.
    /// @param _treasuryAccount Treasury Account providing idle BTC and receiving LP tokens.
    /// @param _sleeve BTC sleeve destination being entered.
    /// @param _request Explicit min-out/min-liquidity bounds for the deposit.
    /// @return result Structured BTC sleeve deposit result.
    function deposit(address _treasuryAccount, address _sleeve, IBTCReserveHandler.BTCDepositRequest calldata _request)
        external
        returns (IBTCReserveHandler.BTCDepositResult memory result)
    {
        address _handler = handlers[_sleeve];
        require(_handler != address(0), MissingBTCHandler(_sleeve));

        result = IBTCReserveHandler(_handler).deposit(_treasuryAccount, msg.sender, _request);
    }

    /// @notice Dispatches a guarded BTC sleeve withdrawal request to the registered handler.
    /// @param _treasuryAccount Treasury Account owning LP tokens and receiving BTC.
    /// @param _sleeve BTC sleeve destination being exited.
    /// @param _request Explicit min-out bounds for the withdrawal.
    /// @return result Structured BTC sleeve withdrawal result.
    function withdraw(
        address _treasuryAccount,
        address _sleeve,
        IBTCReserveHandler.BTCWithdrawRequest calldata _request
    ) external returns (IBTCReserveHandler.BTCWithdrawResult memory result) {
        address _handler = handlers[_sleeve];
        require(_handler != address(0), MissingBTCHandler(_sleeve));

        result = IBTCReserveHandler(_handler).withdraw(_treasuryAccount, msg.sender, _request);
    }

    /// @inheritdoc IBTCReserveRouterAuthority
    function isAuthorizedBTCHandler(address _handler) external view returns (bool) {
        return handlerReferenceCounts[_handler] > 0;
    }
}
