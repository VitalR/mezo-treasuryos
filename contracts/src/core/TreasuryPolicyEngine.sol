// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

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
        require(_factory != address(0), InvalidActor(_factory));
        require(factory == address(0), FactoryAlreadySet(factory));

        factory = _factory;
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function initializeAccount(address _account, address _treasuryAdmin, AccountPolicyConfig calldata _config)
        external
    {
        require(msg.sender == factory, UnauthorizedActor(_account, msg.sender));
        require(_account != address(0), InvalidAccount(_account));
        require(_treasuryAdmin != address(0), InvalidActor(_treasuryAdmin));
        require(_config.operator != address(0), InvalidActor(_config.operator));
        require(_config.approver != address(0), InvalidActor(_config.approver));
        require(_config.operator != _config.approver, InvalidRoleConfiguration());
        require(
            _config.approvedDestinations.length == _config.destinationCaps.length,
            InvalidDestinationConfigLength(_config.approvedDestinations.length, _config.destinationCaps.length)
        );

        AccountPolicy storage policy = accountPolicies[_account];
        require(!policy.initialized, AccountAlreadyInitialized(_account));

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
            require(destination != address(0), InvalidDestination(destination));

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

        require(!policy.paused, PolicyPaused(_account));
        require(_amount > 0, InvalidAmount(_amount));

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

        require(!policy.paused, PolicyPaused(_account));
        require(_amount > 0, InvalidAmount(_amount));
        require(_destination != address(0), InvalidDestination(_destination));
        require(approvedDestinations[_account][_destination], NotApprovedDestination(_destination));

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

        require(!policy.paused, PolicyPaused(_account));
        require(_amount > 0, InvalidAmount(_amount));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_currentAllocation >= _amount, InsufficientAllocation(_destination, _amount, _currentAllocation));

        _requireMovementAuthority(policy, _actor, _amount);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function setPause(address _account, bool _paused) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);
        require(
            msg.sender == _account || msg.sender == policy.approver || msg.sender == policy.treasuryAdmin,
            UnauthorizedActor(_account, msg.sender)
        );

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
        require(policy.initialized, InvalidAccount(_account));
    }

    function _requireBorrowAuthority(AccountPolicy storage _policy, address _actor, uint256 _amount) private view {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        require(_actor == _policy.operator, UnauthorizedActor(address(0), _actor));
        require(_amount <= _policy.approvalThreshold, ApprovalRequired(_actor, _amount, _policy.approvalThreshold));
    }

    function _requireMovementAuthority(AccountPolicy storage _policy, address _actor, uint256 _amount) private view {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        require(_actor == _policy.operator, UnauthorizedActor(address(0), _actor));
        require(_amount <= _policy.approvalThreshold, ApprovalRequired(_actor, _amount, _policy.approvalThreshold));
    }
}
