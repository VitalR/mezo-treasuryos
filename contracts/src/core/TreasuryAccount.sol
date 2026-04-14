// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title TreasuryAccount
/// @notice Client-isolated treasury operating boundary for borrowed and allocated MUSD.
contract TreasuryAccount {
    /// @notice Emitted when borrowed MUSD is recorded into the Treasury Account.
    event BorrowRecorded(uint256 amount, uint256 idleBalanceAfter);
    /// @notice Emitted when the trusted borrow adapter is updated.
    event BorrowAdapterUpdated(address indexed borrowAdapter);
    /// @notice Emitted when the trusted allocation adapter is updated.
    event AllocationAdapterUpdated(address indexed allocationAdapter);

    /// @notice Emitted when idle MUSD is allocated to an approved destination.
    event AllocationExecuted(
        address indexed destination, uint256 amount, uint256 idleBalanceAfter, uint256 allocationAfter
    );

    /// @notice Emitted when deployed MUSD is withdrawn back into the idle treasury balance.
    event WithdrawalExecuted(
        address indexed destination, uint256 amount, uint256 idleBalanceAfter, uint256 allocationAfter
    );

    error InvalidPolicyEngine(address policyEngine);
    error InvalidTreasuryAdmin(address treasuryAdmin);
    error InvalidBorrowAdapter(address borrowAdapter);
    error InvalidAllocationAdapter(address allocationAdapter);
    error UnauthorizedCaller(address caller);

    /// @notice Treasury administrator with authority to configure trusted adapters and direct admin actions.
    address public immutable treasuryAdmin;
    /// @notice TreasuryOS policy engine enforcing internal treasury controls for this account.
    ITreasuryPolicyEngine public immutable policyEngine;
    /// @notice Trusted borrow adapter allowed to route Mezo borrow origination into this account.
    address public borrowAdapter;
    /// @notice Trusted allocation adapter allowed to route destination deposits and withdrawals.
    address public allocationAdapter;

    /// @notice Idle treasury-managed MUSD held inside the account and available for operations.
    uint256 public idleMUSD;
    /// @notice Deployed MUSD amount tracked per approved destination.
    mapping(address destination => uint256 amount) public destinationAllocations;

    /// @param _treasuryAdmin Treasury administrator for the account.
    /// @param _policyEngine Policy engine enforcing TreasuryOS internal controls.
    constructor(address _treasuryAdmin, ITreasuryPolicyEngine _policyEngine) {
        require(_treasuryAdmin != address(0), InvalidTreasuryAdmin(_treasuryAdmin));
        require(address(_policyEngine) != address(0), InvalidPolicyEngine(address(_policyEngine)));

        treasuryAdmin = _treasuryAdmin;
        policyEngine = _policyEngine;
    }

    /// @notice Records a borrow flow into the treasury idle balance.
    /// @param _amount Amount of borrowed MUSD entering the treasury.
    function recordBorrow(uint256 _amount) external {
        require(msg.sender == treasuryAdmin, UnauthorizedCaller(msg.sender));

        policyEngine.validateBorrow(address(this), msg.sender, _amount, idleMUSD);

        idleMUSD += _amount;
        emit BorrowRecorded(_amount, idleMUSD);
    }

    /// @notice Records a borrow flow initiated through the configured borrow adapter.
    /// @param _actor Treasury actor on whose behalf the borrow is being originated.
    /// @param _amount Amount of borrowed MUSD entering the treasury.
    function recordBorrowFromAdapter(address _actor, uint256 _amount) external {
        require(msg.sender == borrowAdapter, UnauthorizedCaller(msg.sender));

        policyEngine.validateBorrow(address(this), _actor, _amount, idleMUSD);

        idleMUSD += _amount;
        emit BorrowRecorded(_amount, idleMUSD);
    }

    /// @notice Allocates idle MUSD into an approved destination.
    /// @param _destination Destination receiving funds.
    /// @param _amount Amount being allocated.
    function allocate(address _destination, uint256 _amount) external {
        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateAllocate(address(this), msg.sender, _destination, _amount, idleMUSD, currentAllocation);

        idleMUSD -= _amount;
        destinationAllocations[_destination] = currentAllocation + _amount;

        emit AllocationExecuted(_destination, _amount, idleMUSD, destinationAllocations[_destination]);
    }

    /// @notice Allocates idle MUSD through the configured allocation adapter on behalf of a treasury actor.
    /// @param _actor Treasury actor on whose behalf the allocation is being performed.
    /// @param _destination Destination receiving funds.
    /// @param _amount Amount being allocated.
    function allocateFromAdapter(address _actor, address _destination, uint256 _amount) external {
        require(msg.sender == allocationAdapter, UnauthorizedCaller(msg.sender));

        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateAllocate(address(this), _actor, _destination, _amount, idleMUSD, currentAllocation);

        idleMUSD -= _amount;
        destinationAllocations[_destination] = currentAllocation + _amount;

        emit AllocationExecuted(_destination, _amount, idleMUSD, destinationAllocations[_destination]);
    }

    /// @notice Withdraws previously allocated MUSD back into the idle treasury balance.
    /// @param _destination Destination being withdrawn from.
    /// @param _amount Amount being withdrawn.
    function withdrawFromDestination(address _destination, uint256 _amount) external {
        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateWithdraw(address(this), msg.sender, _destination, _amount, currentAllocation);

        destinationAllocations[_destination] = currentAllocation - _amount;
        idleMUSD += _amount;

        emit WithdrawalExecuted(_destination, _amount, idleMUSD, destinationAllocations[_destination]);
    }

    /// @notice Withdraws previously allocated MUSD through the configured allocation adapter.
    /// @param _actor Treasury actor on whose behalf the withdrawal is being performed.
    /// @param _destination Destination being withdrawn from.
    /// @param _amount Amount being withdrawn.
    function withdrawFromAdapter(address _actor, address _destination, uint256 _amount) external {
        require(msg.sender == allocationAdapter, UnauthorizedCaller(msg.sender));

        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateWithdraw(address(this), _actor, _destination, _amount, currentAllocation);

        destinationAllocations[_destination] = currentAllocation - _amount;
        idleMUSD += _amount;

        emit WithdrawalExecuted(_destination, _amount, idleMUSD, destinationAllocations[_destination]);
    }

    /// @notice Updates the paused state of the Treasury Account.
    /// @param _paused New paused state.
    function setPause(bool _paused) external {
        (,, address approver,,,,,) = policyEngine.getAccountPolicy(address(this));
        require(msg.sender == treasuryAdmin || msg.sender == approver, UnauthorizedCaller(msg.sender));

        policyEngine.setPause(address(this), _paused);
    }

    /// @notice Sets the trusted borrow adapter for TreasuryOS-originated Mezo borrow flows.
    /// @param _borrowAdapter Borrow adapter allowed to record borrowed MUSD on behalf of treasury actors.
    function setBorrowAdapter(address _borrowAdapter) external {
        require(msg.sender == treasuryAdmin, UnauthorizedCaller(msg.sender));
        require(_borrowAdapter != address(0), InvalidBorrowAdapter(_borrowAdapter));

        borrowAdapter = _borrowAdapter;
        emit BorrowAdapterUpdated(_borrowAdapter);
    }

    /// @notice Sets the trusted allocation adapter for routed deployment and withdrawal flows.
    /// @param _allocationAdapter Allocation adapter allowed to mutate treasury allocation state.
    function setAllocationAdapter(address _allocationAdapter) external {
        require(msg.sender == treasuryAdmin, UnauthorizedCaller(msg.sender));
        require(_allocationAdapter != address(0), InvalidAllocationAdapter(_allocationAdapter));

        allocationAdapter = _allocationAdapter;
        emit AllocationAdapterUpdated(_allocationAdapter);
    }
}
