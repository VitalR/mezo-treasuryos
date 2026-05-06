// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title TreasuryPolicyEngine
/// @notice Enforces TreasuryOS internal controls for Treasury Account actions.
contract TreasuryPolicyEngine is ITreasuryPolicyEngine {
    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when a Treasury Account is initialized in the policy engine.
    event AccountPolicyInitialized(
        address indexed account,
        address indexed treasuryAdmin,
        address indexed operator,
        address approver,
        uint256 liquidityBuffer,
        uint256 approvalThreshold,
        uint256 warningCollateralRatioBps,
        uint256 criticalCollateralRatioBps,
        bool automationEnabled,
        bool startPaused
    );

    /// @notice Emitted when the dedicated automation executor changes for an account.
    event AutomationExecutorUpdated(
        address indexed account, address indexed previousExecutor, address indexed newExecutor
    );
    /// @notice Emitted when treasury health thresholds change for an account.
    event AutomationThresholdsUpdated(
        address indexed account, uint256 warningCollateralRatioBps, uint256 criticalCollateralRatioBps
    );
    /// @notice Emitted when automation action-size limits change for an account.
    event AutomationLimitsUpdated(address indexed account, uint256 maxAutoBufferRestore, uint256 maxAutoDebtRepay);
    /// @notice Emitted when automation capabilities change for an account.
    event AutomationCapabilitiesUpdated(
        address indexed account, bool allowAutoSavingsWithdraw, bool allowAutoDebtRepay
    );
    /// @notice Emitted when a destination approval or allocation cap changes for an account.
    event DestinationPolicyUpdated(
        address indexed account, address indexed destination, address indexed actor, bool approved, uint256 cap
    );
    /// @notice Emitted when the automation-enabled state changes for an account.
    event AutomationEnabledUpdated(address indexed account, bool automationEnabled);
    /// @notice Emitted when the paused state changes for an account.
    event PauseUpdated(address indexed account, bool paused);
    /// @notice Emitted when the treasury administrator for an account is updated.
    event TreasuryAdminUpdated(
        address indexed account, address indexed previousTreasuryAdmin, address indexed newTreasuryAdmin
    );

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when policy initialization is attempted more than once for the same account.
    /// @param account Treasury Account already initialized in the policy engine.
    error AccountAlreadyInitialized(address account);
    /// @notice Raised when an operator attempts to move more than the configured approval threshold.
    /// @param actor Treasury actor attempting the movement.
    /// @param amount Requested movement amount.
    /// @param threshold Configured operator approval threshold.
    error ApprovalRequired(address actor, uint256 amount, uint256 threshold);
    /// @notice Raised when automation is disabled for an account.
    /// @param account Treasury Account whose automation policy blocks the action.
    error AutomationDisabled(address account);
    /// @notice Raised when automated buffer restoration is disabled for an account.
    /// @param account Treasury Account whose automation policy blocks the action.
    error AutoSavingsWithdrawDisabled(address account);
    /// @notice Raised when automated debt repayment is disabled for an account.
    /// @param account Treasury Account whose automation policy blocks the action.
    error AutoDebtRepayDisabled(address account);
    /// @notice Raised when a destination allocation exceeds the configured cap.
    /// @param nextAllocation Proposed post-action allocation.
    /// @param cap Configured destination cap.
    error AllocationCapExceeded(uint256 nextAllocation, uint256 cap);
    /// @notice Raised when the factory is configured more than once.
    /// @param factory Previously configured factory address.
    error FactoryAlreadySet(address factory);
    /// @notice Raised when a destination withdrawal or settlement exceeds tracked allocation.
    /// @param destination Destination being reduced.
    /// @param amount Requested allocation reduction.
    /// @param currentAllocation Current tracked allocation.
    error InsufficientAllocation(address destination, uint256 amount, uint256 currentAllocation);
    /// @notice Raised when idle MUSD is insufficient for the requested action.
    /// @param amount Requested MUSD amount.
    /// @param idleBalance Current idle treasury balance.
    error InsufficientIdleBalance(uint256 amount, uint256 idleBalance);
    /// @notice Raised when an unknown Treasury Account is referenced.
    /// @param account Treasury Account address being checked.
    error InvalidAccount(address account);
    /// @notice Raised when a required actor address is zero.
    /// @param actor Invalid actor address.
    error InvalidActor(address actor);
    /// @notice Raised when an action amount is zero or otherwise invalid.
    /// @param amount Invalid amount value.
    error InvalidAmount(uint256 amount);
    /// @notice Raised when a destination address is zero or otherwise invalid.
    /// @param destination Invalid destination address.
    error InvalidDestination(address destination);
    /// @notice Raised when destination approval and cap arrays have different lengths.
    /// @param destinations Number of approved destinations supplied.
    /// @param caps Number of destination caps supplied.
    error InvalidDestinationConfigLength(uint256 destinations, uint256 caps);
    /// @notice Raised when treasury warning and critical collateral thresholds are invalid.
    /// @param warningCollateralRatioBps Proposed warning threshold in basis points.
    /// @param criticalCollateralRatioBps Proposed critical threshold in basis points.
    error InvalidRiskThresholds(uint256 warningCollateralRatioBps, uint256 criticalCollateralRatioBps);
    /// @notice Raised when an automated action amount exceeds its configured bound.
    /// @param actionType Encoded workflow category being checked.
    /// @param amount Requested automation amount.
    /// @param limit Configured automation limit.
    error AutomationLimitExceeded(bytes32 actionType, uint256 amount, uint256 limit);
    /// @notice Raised when operator and approver roles are configured inconsistently.
    error InvalidRoleConfiguration();
    /// @notice Raised when an allocation would breach the minimum idle liquidity buffer.
    /// @param nextIdleBalance Proposed post-action idle balance.
    /// @param requiredBuffer Configured minimum liquidity buffer.
    error LiquidityBufferBreached(uint256 nextIdleBalance, uint256 requiredBuffer);
    /// @notice Raised when a destination is not approved for treasury allocation.
    /// @param destination Destination being checked.
    error NotApprovedDestination(address destination);
    /// @notice Raised when a paused treasury attempts a blocked action.
    /// @param account Treasury Account currently paused.
    error PolicyPaused(address account);
    /// @notice Raised when a caller lacks the authority required for an action.
    /// @param account Treasury Account being protected.
    /// @param actor Caller attempting the action.
    error UnauthorizedActor(address account, address actor);

    // =============================================================
    // Types
    // =============================================================

    /// @notice Per-account treasury policy state enforced by the policy engine.
    /// @param treasuryAdmin Treasury administrator for the account.
    /// @param operator Operator allowed to execute lower-risk treasury actions.
    /// @param approver Approver allowed to authorize larger or more sensitive actions.
    /// @param liquidityBuffer Minimum idle MUSD that must remain undeployed.
    /// @param approvalThreshold Maximum amount an operator may move without approver authority.
    /// @param warningCollateralRatioBps Treasury-defined warning threshold for collateral health, in basis points.
    /// @param criticalCollateralRatioBps Treasury-defined critical threshold for collateral health, in basis points.
    /// @param automationEnabled Whether low-risk automation is enabled.
    /// @param paused Whether treasury actions are currently paused.
    /// @param initialized Whether the account has been initialized in the policy engine.
    struct AccountPolicy {
        address treasuryAdmin;
        address operator;
        address approver;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
        uint256 warningCollateralRatioBps;
        uint256 criticalCollateralRatioBps;
        address automationExecutor;
        uint256 maxAutoBufferRestore;
        uint256 maxAutoDebtRepay;
        bool allowAutoSavingsWithdraw;
        bool allowAutoDebtRepay;
        bool automationEnabled;
        bool paused;
        bool initialized;
    }

    // =============================================================
    // Storage
    // =============================================================

    /// @notice Policy configuration stored per Treasury Account.
    mapping(address account => AccountPolicy policy) private accountPolicies;
    /// @notice Destination approval state stored per Treasury Account.
    mapping(address account => mapping(address destination => bool approved)) private approvedDestinations;
    /// @notice Allocation caps stored per Treasury Account and destination.
    mapping(address account => mapping(address destination => uint256 cap)) private destinationCaps;
    /// @notice Treasury Account factory allowed to initialize new accounts.
    address public factory;

    // =============================================================
    // External Functions
    // =============================================================

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
            _config.warningCollateralRatioBps > _config.criticalCollateralRatioBps
                && _config.criticalCollateralRatioBps > 0,
            InvalidRiskThresholds(_config.warningCollateralRatioBps, _config.criticalCollateralRatioBps)
        );
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
        policy.warningCollateralRatioBps = _config.warningCollateralRatioBps;
        policy.criticalCollateralRatioBps = _config.criticalCollateralRatioBps;
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
            _config.warningCollateralRatioBps,
            _config.criticalCollateralRatioBps,
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
    function updateAutomationExecutor(address _account, address _executor) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);

        address _previousExecutor = policy.automationExecutor;
        policy.automationExecutor = _executor;

        emit AutomationExecutorUpdated(_account, _previousExecutor, _executor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function updateAutomationThresholds(
        address _account,
        uint256 _warningCollateralRatioBps,
        uint256 _criticalCollateralRatioBps
    ) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);
        require(
            _warningCollateralRatioBps > _criticalCollateralRatioBps && _criticalCollateralRatioBps > 0,
            InvalidRiskThresholds(_warningCollateralRatioBps, _criticalCollateralRatioBps)
        );

        policy.warningCollateralRatioBps = _warningCollateralRatioBps;
        policy.criticalCollateralRatioBps = _criticalCollateralRatioBps;

        emit AutomationThresholdsUpdated(_account, _warningCollateralRatioBps, _criticalCollateralRatioBps);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function updateAutomationLimits(address _account, uint256 _maxAutoBufferRestore, uint256 _maxAutoDebtRepay)
        external
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);

        policy.maxAutoBufferRestore = _maxAutoBufferRestore;
        policy.maxAutoDebtRepay = _maxAutoDebtRepay;

        emit AutomationLimitsUpdated(_account, _maxAutoBufferRestore, _maxAutoDebtRepay);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function updateAutomationCapabilities(address _account, bool _allowAutoSavingsWithdraw, bool _allowAutoDebtRepay)
        external
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);

        policy.allowAutoSavingsWithdraw = _allowAutoSavingsWithdraw;
        policy.allowAutoDebtRepay = _allowAutoDebtRepay;

        emit AutomationCapabilitiesUpdated(_account, _allowAutoSavingsWithdraw, _allowAutoDebtRepay);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function updateDestinationPolicy(address _account, address _destination, bool _approved, uint256 _cap) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);
        require(_destination != address(0), InvalidDestination(_destination));

        approvedDestinations[_account][_destination] = _approved;
        destinationCaps[_account][_destination] = _approved ? _cap : 0;

        emit DestinationPolicyUpdated(
            _account, _destination, msg.sender, _approved, destinationCaps[_account][_destination]
        );
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function updateAutomationEnabled(address _account, bool _automationEnabled) external {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAdminAuthority(policy, _account, msg.sender);

        policy.automationEnabled = _automationEnabled;

        emit AutomationEnabledUpdated(_account, _automationEnabled);
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
    function validateAutomationExecution(address _account, address _actor) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        _requireAutomationAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateBufferRestore(address _account, address _actor, address _destination, uint256 _amount)
        external
        view
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(_destination != address(0), InvalidDestination(_destination));
        require(approvedDestinations[_account][_destination], NotApprovedDestination(_destination));
        require(_amount > 0, InvalidAmount(_amount));

        if (_actor == policy.automationExecutor) {
            _requireAutomationAuthority(policy, _account, _actor);
            require(policy.allowAutoSavingsWithdraw, AutoSavingsWithdrawDisabled(_account));
            require(
                _amount <= policy.maxAutoBufferRestore,
                AutomationLimitExceeded(bytes32("BUFFER_RESTORE"), _amount, policy.maxAutoBufferRestore)
            );
            return;
        }

        _requireElevatedAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateDeRiskRepayment(address _account, address _actor, address _destination, uint256 _amount)
        external
        view
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(_destination != address(0), InvalidDestination(_destination));
        require(approvedDestinations[_account][_destination], NotApprovedDestination(_destination));
        require(_amount > 0, InvalidAmount(_amount));

        if (_actor == policy.automationExecutor) {
            _requireAutomationAuthority(policy, _account, _actor);
            require(policy.allowAutoDebtRepay, AutoDebtRepayDisabled(_account));
            require(
                _amount <= policy.maxAutoDebtRepay,
                AutomationLimitExceeded(bytes32("DEBT_REPAY"), _amount, policy.maxAutoDebtRepay)
            );
            return;
        }

        _requireElevatedAuthority(policy, _account, _actor);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function validateDisbursement(
        address _account,
        address _actor,
        address _recipient,
        uint256 _amount,
        uint256 _idleBalance
    ) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(!policy.paused, PolicyPaused(_account));
        require(_recipient != address(0), InvalidDestination(_recipient));
        require(_amount > 0, InvalidAmount(_amount));
        require(_idleBalance >= _amount, InsufficientIdleBalance(_amount, _idleBalance));

        _requireMovementAuthority(policy, _account, _actor, _amount);
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
        require(_idleBalance >= _amount, InsufficientIdleBalance(_amount, _idleBalance));

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
    function validateWithdrawalSettlement(
        address _account,
        address _actor,
        address _destination,
        uint256 _allocationAmount,
        uint256 _currentAllocation
    ) external view {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        require(!policy.paused, PolicyPaused(_account));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_allocationAmount > 0, InvalidAmount(_allocationAmount));
        require(
            _currentAllocation >= _allocationAmount,
            InsufficientAllocation(_destination, _allocationAmount, _currentAllocation)
        );

        _requireMovementAuthority(policy, _account, _actor, _allocationAmount);
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

    // =============================================================
    // View Functions
    // =============================================================

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

    /// @inheritdoc ITreasuryPolicyEngine
    function getAccountRiskPolicy(address _account)
        external
        view
        returns (uint256 warningCollateralRatioBps, uint256 criticalCollateralRatioBps)
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        return (policy.warningCollateralRatioBps, policy.criticalCollateralRatioBps);
    }

    /// @inheritdoc ITreasuryPolicyEngine
    function getAccountAutomationPolicy(address _account)
        external
        view
        returns (
            address automationExecutor,
            uint256 maxAutoBufferRestore,
            uint256 maxAutoDebtRepay,
            bool allowAutoSavingsWithdraw,
            bool allowAutoDebtRepay
        )
    {
        AccountPolicy storage policy = _requireInitializedAccount(_account);

        return (
            policy.automationExecutor,
            policy.maxAutoBufferRestore,
            policy.maxAutoDebtRepay,
            policy.allowAutoSavingsWithdraw,
            policy.allowAutoDebtRepay
        );
    }

    // =============================================================
    // Private Functions
    // =============================================================

    /// @notice Returns initialized policy state for an account or reverts if the account is unknown.
    /// @param _account Treasury Account being checked.
    /// @return policy Storage pointer to the account policy state.
    function _requireInitializedAccount(address _account) private view returns (AccountPolicy storage policy) {
        policy = accountPolicies[_account];
        require(policy.initialized, InvalidAccount(_account));
    }

    /// @notice Validates that a caller may update critical treasury configuration for an account.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the configuration change.
    function _requireAdminAuthority(AccountPolicy storage _policy, address _account, address _actor) private view {
        require(_actor == _account || _actor == _policy.treasuryAdmin, UnauthorizedActor(_account, _actor));
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

    /// @notice Validates whether an actor may execute bounded automated treasury workflows.
    /// @param _policy Account policy state being enforced.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the automation action.
    function _requireAutomationAuthority(AccountPolicy storage _policy, address _account, address _actor) private view {
        require(_policy.automationEnabled, AutomationDisabled(_account));
        require(!_policy.paused, PolicyPaused(_account));

        if (_actor == _policy.treasuryAdmin) {
            return;
        }

        require(_actor == _policy.automationExecutor, UnauthorizedActor(_account, _actor));
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
