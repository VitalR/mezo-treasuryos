// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITreasuryPolicyEngine} from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title TreasuryPolicyEngine
/// @notice Enforces TreasuryOS internal controls for Treasury Account actions.
contract TreasuryPolicyEngine is ITreasuryPolicyEngine {
    /// @notice Emitted when a Treasury Account is initialized in the policy engine.
    event AccountPolicyInitialized(
        address indexed account,
        address indexed treasuryAdmin,
        address indexed operator,
        address approver,
        uint256 liquidityBuffer,
        uint256 approvalThreshold,
        bool automationEnabled,
        bool startPaused
    );

    /// @notice Emitted when the paused state changes for an account.
    event PauseUpdated(address indexed account, bool paused);

    error AccountAlreadyInitialized(address account);
    error ApprovalRequired(address actor, uint256 amount, uint256 threshold);
    error FactoryAlreadySet(address factory);
    error InsufficientAllocation(address destination, uint256 amount, uint256 currentAllocation);
    error InvalidAccount(address account);
    error InvalidActor(address actor);
    error InvalidAmount(uint256 amount);
    error InvalidDestination(address destination);
    error InvalidDestinationConfigLength(uint256 destinations, uint256 caps);
    error InvalidRoleConfiguration();
    error LiquidityBufferBreached(uint256 nextIdleBalance, uint256 requiredBuffer);
    error NotApprovedDestination(address destination);
    error PolicyPaused(address account);
    error AllocationCapExceeded(uint256 nextAllocation, uint256 cap);
    error UnauthorizedActor(address account, address actor);

    struct AccountPolicy {
        address treasuryAdmin;
        address operator;
        address approver;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
        bool automationEnabled;
        bool paused;
        bool initialized;
    }

    mapping(address account => AccountPolicy policy) private accountPolicies;
    mapping(address account => mapping(address destination => bool approved)) private approvedDestinations;
    mapping(address account => mapping(address destination => uint256 cap)) private destinationCaps;
    address public factory;

    /// @inheritdoc ITreasuryPolicyEngine
    function setFactory(address _factory) external {
        if (_factory == address(0)) {
            revert InvalidActor(_factory);
        }
        if (factory != address(0)) {
            revert FactoryAlreadySet(factory);
        }

        factory = _factory;
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function initializeAccount(address _account, address _treasuryAdmin, AccountPolicyConfig calldata _config)
        external
    {
        if (msg.sender != factory) {
            revert UnauthorizedActor(_account, msg.sender);
        }
        if (_account == address(0)) {
            revert InvalidAccount(_account);
        }
        if (_treasuryAdmin == address(0)) {
            revert InvalidActor(_treasuryAdmin);
        }
        if (_config.operator == address(0)) {
            revert InvalidActor(_config.operator);
        }
        if (_config.approver == address(0)) {
            revert InvalidActor(_config.approver);
        }
        if (_config.operator == _config.approver) {
            revert InvalidRoleConfiguration();
        }
        if (_config.approvedDestinations.length != _config.destinationCaps.length) {
            revert InvalidDestinationConfigLength(_config.approvedDestinations.length, _config.destinationCaps.length);
        }

        AccountPolicy storage policy = accountPolicies[_account];
        if (policy.initialized) {
            revert AccountAlreadyInitialized(_account);
        }

        policy.treasuryAdmin = _treasuryAdmin;
        policy.operator = _config.operator;
        policy.approver = _config.approver;
        policy.liquidityBuffer = _config.liquidityBuffer;
        policy.approvalThreshold = _config.approvalThreshold;
        policy.automationEnabled = _config.automationEnabled;
        policy.paused = _config.startPaused;
        policy.initialized = true;

        uint256 destinationCount = _config.approvedDestinations.length;
        for (uint256 i = 0; i < destinationCount; ++i) {
            address destination = _config.approvedDestinations[i];
            if (destination == address(0)) {
                revert InvalidDestination(destination);
            }

            approvedDestinations[_account][destination] = true;
            destinationCaps[_account][destination] = _config.destinationCaps[i];
        }

        emit AccountPolicyInitialized(
            _account,
            _treasuryAdmin,
            _config.operator,
            _config.approver,
            _config.liquidityBuffer,
            _config.approvalThreshold,
            _config.automationEnabled,
            _config.startPaused
        );
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateBorrow(address _account, address _actor, uint256 _amount, uint256) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        if (policy.paused) {
            revert PolicyPaused(_account);
        }
        if (_amount == 0) {
            revert InvalidAmount(_amount);
        }

        _requireBorrowAuthority(policy, _actor, _amount);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateAllocate(
        address _account,
        address _actor,
        address _destination,
        uint256 _amount,
        uint256 _idleBalance,
        uint256 _currentAllocation
    ) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        if (policy.paused) {
            revert PolicyPaused(_account);
        }
        if (_amount == 0) {
            revert InvalidAmount(_amount);
        }
        if (_destination == address(0)) {
            revert InvalidDestination(_destination);
        }
        if (!approvedDestinations[_account][_destination]) {
            revert NotApprovedDestination(_destination);
        }

        _requireMovementAuthority(policy, _actor, _amount);

        uint256 nextIdleBalance = _idleBalance - _amount;
        if (nextIdleBalance < policy.liquidityBuffer) {
            revert LiquidityBufferBreached(nextIdleBalance, policy.liquidityBuffer);
        }

        uint256 nextAllocation = _currentAllocation + _amount;
        uint256 cap = destinationCaps[_account][_destination];
        if (nextAllocation > cap) {
            revert AllocationCapExceeded(nextAllocation, cap);
        }
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateWithdraw(
        address _account,
        address _actor,
        address _destination,
        uint256 _amount,
        uint256 _currentAllocation
    ) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        if (policy.paused) {
            revert PolicyPaused(_account);
        }
        if (_amount == 0) {
            revert InvalidAmount(_amount);
        }
        if (_destination == address(0)) {
            revert InvalidDestination(_destination);
        }
        if (_currentAllocation < _amount) {
            revert InsufficientAllocation(_destination, _amount, _currentAllocation);
        }

        _requireMovementAuthority(policy, _actor, _amount);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function setPause(address _account, bool _paused) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);
        if (msg.sender != _account && msg.sender != policy.approver && msg.sender != policy.treasuryAdmin) {
            revert UnauthorizedActor(_account, msg.sender);
        }

        policy.paused = _paused;
        emit PauseUpdated(_account, _paused);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function isDestinationApproved(address _account, address _destination) external view returns (bool) {
        return approvedDestinations[_account][_destination];
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function allocationCap(address _account, address _destination) external view returns (uint256) {
        return destinationCaps[_account][_destination];
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function getAccountPolicy(address _account)
        external
        view
        returns (
            address treasuryAdmin,
            address operator,
            address approver,
            uint256 liquidityBuffer,
            uint256 approvalThreshold,
            bool automationEnabled,
            bool paused,
            bool initialized
        )
    {
        AccountPolicy storage policy = accountPolicies[_account];

        return (
            policy.treasuryAdmin,
            policy.operator,
            policy.approver,
            policy.liquidityBuffer,
            policy.approvalThreshold,
            policy.automationEnabled,
            policy.paused,
            policy.initialized
        );
    }

    function _requireInitializedAccount(address _account) private view returns (AccountPolicy storage policy) {
        policy = accountPolicies[_account];
        if (!policy.initialized) {
            revert InvalidAccount(_account);
        }
    }

    function _requireBorrowAuthority(AccountPolicy storage _policy, address _actor, uint256 _amount) private view {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        if (_actor != _policy.operator) {
            revert UnauthorizedActor(address(0), _actor);
        }
        if (_amount > _policy.approvalThreshold) {
            revert ApprovalRequired(_actor, _amount, _policy.approvalThreshold);
        }
    }

    function _requireMovementAuthority(AccountPolicy storage _policy, address _actor, uint256 _amount) private view {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        if (_actor != _policy.operator) {
            revert UnauthorizedActor(address(0), _actor);
        }
        if (_amount > _policy.approvalThreshold) {
            revert ApprovalRequired(_actor, _amount, _policy.approvalThreshold);
        }
    }
}
