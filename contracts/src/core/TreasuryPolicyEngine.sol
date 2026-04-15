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
    /// @notice Emitted when the treasury administrator for an account is updated.
    event TreasuryAdminUpdated(
        address indexed account, address indexed previousTreasuryAdmin, address indexed newTreasuryAdmin
    );

    error AccountAlreadyInitialized(address account);
    error ApprovalRequired(address actor, uint256 amount, uint256 threshold);
    error FactoryAlreadySet(address factory);
    error InsufficientAllocation(address destination, uint256 amount, uint256 currentAllocation);
    error InsufficientIdleBalance(uint256 amount, uint256 idleBalance);
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

    /// @notice Per-account treasury policy state enforced by the policy engine.
    /// @param treasuryAdmin Treasury administrator for the account.
    /// @param operator Operator allowed to execute lower-risk treasury actions.
    /// @param approver Approver allowed to authorize larger or more sensitive actions.
    /// @param liquidityBuffer Minimum idle MUSD that must remain undeployed.
    /// @param approvalThreshold Maximum amount an operator may move without approver authority.
    /// @param automationEnabled Whether low-risk automation is enabled.
    /// @param paused Whether treasury actions are currently paused.
    /// @param initialized Whether the account has been initialized in the policy engine.
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

    /// @notice Policy configuration stored per Treasury Account.
    mapping(address account => AccountPolicy policy) private accountPolicies;
    /// @notice Destination approval state stored per Treasury Account.
    mapping(address account => mapping(address destination => bool approved)) private approvedDestinations;
    /// @notice Allocation caps stored per Treasury Account and destination.
    mapping(address account => mapping(address destination => uint256 cap)) private destinationCaps;
    /// @notice Treasury Account factory allowed to initialize new accounts.
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

        for (uint256 _i = 0; _i < _config.approvedDestinations.length; _i++) {
            address _destination = _config.approvedDestinations[_i];
            require(_destination != address(0), InvalidDestination(_destination));

            approvedDestinations[_account][_destination] = true;
            destinationCaps[_account][_destination] = _config.destinationCaps[_i];
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
    function updateTreasuryAdmin(address _account, address _treasuryAdmin) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(msg.sender == _account, UnauthorizedActor(_account, msg.sender));
        require(_treasuryAdmin != address(0), InvalidActor(_treasuryAdmin));

        address _previousTreasuryAdmin = policy.treasuryAdmin;
        policy.treasuryAdmin = _treasuryAdmin;

        emit TreasuryAdminUpdated(_account, _previousTreasuryAdmin, _treasuryAdmin);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateBorrow(address _account, address _actor, uint256 _amount, uint256) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(!policy.paused, PolicyPaused(_account));
        require(_amount > 0, InvalidAmount(_amount));

        _requireBorrowAuthority(policy, _account, _actor, _amount);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateDebtRepayment(address _account, address _actor, uint256 _amount, uint256 _idleBalance)
        external
        view
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(_amount > 0, InvalidAmount(_amount));
        require(_idleBalance >= _amount, InsufficientIdleBalance(_amount, _idleBalance));

        _requireMovementAuthority(policy, _account, _actor, _amount);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateCollateralDeposit(address _account, address _actor, uint256 _amount) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(_amount > 0, InvalidAmount(_amount));
        _requireRiskReducingAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateCollateralWithdrawal(address _account, address _actor, uint256 _amount) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(!policy.paused, PolicyPaused(_account));
        require(_amount > 0, InvalidAmount(_amount));

        _requireElevatedAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateClosePosition(address _account, address _actor, uint256 _idleBalance, uint256 _positionCloseDebt)
        external
        view
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(_idleBalance >= _positionCloseDebt, InsufficientIdleBalance(_positionCloseDebt, _idleBalance));
        _requireElevatedAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateYieldClaim(address _account, address _actor) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireRiskReducingAuthority(policy, _account, _actor);
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

        _requireMovementAuthority(policy, _account, _actor, _amount);

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

        _requireMovementAuthority(policy, _account, _actor, _amount);
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

    /// @notice Returns initialized policy state for an account or reverts if the account is unknown.
    /// @param _account Treasury Account being checked.
    /// @return policy Storage pointer to the account policy state.
    function _requireInitializedAccount(address _account) private view returns (AccountPolicy storage policy) {
        policy = accountPolicies[_account];
        require(policy.initialized, InvalidAccount(_account));
    }

    /// @notice Validates whether an actor may originate or increase debt for the requested amount.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Treasury actor attempting the borrow.
    /// @param _amount Borrow amount being requested.
    function _requireBorrowAuthority(AccountPolicy storage _policy, address _account, address _actor, uint256 _amount)
        private
        view
    {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        require(_actor == _policy.operator, UnauthorizedActor(_account, _actor));
        require(_amount <= _policy.approvalThreshold, ApprovalRequired(_actor, _amount, _policy.approvalThreshold));
    }

    /// @notice Validates whether an actor may move treasury funds for the requested amount.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Treasury actor attempting the movement.
    /// @param _amount Allocation, withdrawal, or repayment amount being requested.
    function _requireMovementAuthority(AccountPolicy storage _policy, address _account, address _actor, uint256 _amount)
        private
        view
    {
        if (_actor == _policy.treasuryAdmin || _actor == _policy.approver) {
            return;
        }

        require(_actor == _policy.operator, UnauthorizedActor(_account, _actor));
        require(_amount <= _policy.approvalThreshold, ApprovalRequired(_actor, _amount, _policy.approvalThreshold));
    }

    /// @notice Validates whether an actor may perform a risk-reducing action.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Treasury actor attempting the action.
    function _requireRiskReducingAuthority(AccountPolicy storage _policy, address _account, address _actor)
        private
        view
    {
        require(
            _actor == _policy.treasuryAdmin || _actor == _policy.approver || _actor == _policy.operator,
            UnauthorizedActor(_account, _actor)
        );
    }

    /// @notice Validates whether an actor has elevated authority for sensitive position actions.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Treasury actor attempting the action.
    function _requireElevatedAuthority(AccountPolicy storage _policy, address _account, address _actor) private view {
        require(_actor == _policy.treasuryAdmin || _actor == _policy.approver, UnauthorizedActor(_account, _actor));
    }
}
