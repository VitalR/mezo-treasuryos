// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";

interface ITreasuryAccountHandlerExecution {
    function executeFromHandler(address _target, uint256 _value, bytes calldata _data)
        external
        returns (bytes memory result);
}

/// @title NativeBTCRecoveryHandler
/// @notice Legacy-only helper for recovering native BTC from a retired TreasuryAccount without idle BTC withdrawal.
/// @dev Register this handler only on a treasury-owned router and remove it after recovery if the old stack remains
/// used.
contract NativeBTCRecoveryHandler is IAllocationHandler {
    error InvalidAddress(address account);
    error InvalidAmount(uint256 amount);
    error UnauthorizedCaller(address caller);

    event NativeBTCRecovered(
        address indexed treasuryAccount, address indexed actor, address indexed recipient, uint256 amount
    );

    address public immutable allocationRouter;
    address public immutable override destination;

    constructor(address _allocationRouter, address _recipient) {
        require(_allocationRouter != address(0), InvalidAddress(_allocationRouter));
        require(_recipient != address(0), InvalidAddress(_recipient));

        allocationRouter = _allocationRouter;
        destination = _recipient;
    }

    function deposit(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 result) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidAddress(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        ITreasuryAccountHandlerExecution(_treasuryAccount).executeFromHandler(destination, _amount, "");

        emit NativeBTCRecovered(_treasuryAccount, _actor, destination, _amount);

        return _amount;
    }

    function withdraw(address, address, uint256) external pure returns (uint256) {
        revert UnauthorizedCaller(address(0));
    }

    function withdrawForWorkflow(address, address, uint256) external pure returns (uint256) {
        revert UnauthorizedCaller(address(0));
    }

    function claimYield(address, address) external pure returns (uint256) {
        return 0;
    }
}
