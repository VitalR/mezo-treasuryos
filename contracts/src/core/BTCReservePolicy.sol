// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title IBTCTreasuryHealthView
/// @notice Minimal Treasury Account health surface used for BTC allocation previews.
interface IBTCTreasuryHealthView {
    /// @notice Returns the current BTC collateral ratio in basis points when available.
    function collateralRatioBps() external view returns (uint256);
}

/// @title BTCReservePolicy
/// @notice BTC-denominated reserve and sleeve policy scaffold for TreasuryOS.
/// @dev This contract does not execute BTC movements. It records BTC bucket accounting, sleeve risk metadata,
///      and preview decisions so BTC-correlated yield candidates can be reviewed without overloading MUSD policy.
contract BTCReservePolicy {
    // =============================================================
    // Constants
    // =============================================================

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    // =============================================================
    // Types
    // =============================================================

    /// @notice Risk category assigned to a BTC-denominated sleeve candidate.
    enum BTCSleeveRiskClass {
        /// @notice Sleeve is disabled and cannot receive BTC principal.
        DISABLED,
        /// @notice Sleeve is intended to preserve BTC-correlated exposure, such as mcbBTC/BTC.
        BTC_CORRELATED,
        /// @notice Sleeve changes pure BTC exposure through BTC/stable or similar LP exposure.
        BTC_DIRECTIONAL_LP,
        /// @notice Sleeve is speculative and blocked by default in V1 policy.
        SPECULATIVE,
        /// @notice Sleeve routes to an external vault and requires separate due diligence.
        EXTERNAL_VAULT
    }

    /// @notice Machine-readable BTC allocation preview decision.
    enum BTCAllocationDecisionCode {
        /// @notice Allocation passes the current BTC reserve policy preview.
        Allowed,
        /// @notice Treasury has no initialized BTC reserve policy.
        PolicyNotConfigured,
        /// @notice BTC yield allocation is paused for the treasury.
        YieldPaused,
        /// @notice Requested BTC amount is zero.
        ZeroAmount,
        /// @notice Sleeve address is invalid.
        InvalidSleeve,
        /// @notice Sleeve is not enabled for BTC allocation.
        SleeveDisabled,
        /// @notice Sleeve is speculative and blocked by default.
        SpeculativeDisabled,
        /// @notice Reported emergency BTC reserve is below the required emergency bucket.
        EmergencyReserveShortfall,
        /// @notice Requested allocation would use BTC needed for the idle reserve floor.
        InsufficientIdleBTCReserve,
        /// @notice No BTC has been accounted for the treasury.
        NoAccountedBTC,
        /// @notice Requested allocation would exceed the aggregate BTC yield cap.
        TotalYieldCapExceeded,
        /// @notice Requested allocation would exceed the sleeve-level BTC cap.
        PerSleeveCapExceeded,
        /// @notice Requested allocation would exceed the directional BTC exposure cap.
        DirectionalCapExceeded,
        /// @notice BTC-correlated asset depeg exceeds policy tolerance.
        AssetDepegExceeded,
        /// @notice Treasury collateral health is below the configured warning ratio.
        CollateralHealthWarning
    }

    /// @notice BTC-denominated treasury buckets used for reserve and yield planning.
    /// @param idleBTCReserve BTC held idle and available only after reserve floors are met.
    /// @param collateralBTC BTC locked as Mezo collateral.
    /// @param emergencyBTCReserve BTC reserved for emergency liquidity, excluded from yield allocation.
    /// @param yieldActiveBTC BTC principal currently deployed to BTC-denominated sleeve exposure.
    /// @param pendingWithdrawBTC BTC principal requested for withdrawal but not yet back in idle reserve.
    struct BTCReserveBuckets {
        uint256 idleBTCReserve;
        uint256 collateralBTC;
        uint256 emergencyBTCReserve;
        uint256 yieldActiveBTC;
        uint256 pendingWithdrawBTC;
    }

    /// @notice Per-treasury BTC reserve and yield policy.
    /// @param minIdleBTCReserve Minimum idle BTC reserve that must remain unallocated.
    /// @param emergencyBTCReserve Minimum emergency BTC bucket required before new BTC yield allocation.
    /// @param maxYieldBTCBps Maximum aggregate BTC yield-active exposure as a share of accounted BTC.
    /// @param maxPerSleeveBTCBps Maximum exposure to any single BTC sleeve as a share of accounted BTC.
    /// @param maxDirectionalBTCBps Maximum directional BTC LP exposure as a share of accounted BTC.
    /// @param maxBTCAssetDepegBps Maximum tolerated BTC-correlated asset depeg in basis points.
    /// @param collateralWarningCRBps Collateral ratio below which BTC yield previews are blocked.
    /// @param btcYieldPaused Whether BTC yield allocation previews should be blocked.
    /// @param initialized Whether this policy has been configured.
    struct BTCReservePolicyConfig {
        uint256 minIdleBTCReserve;
        uint256 emergencyBTCReserve;
        uint256 maxYieldBTCBps;
        uint256 maxPerSleeveBTCBps;
        uint256 maxDirectionalBTCBps;
        uint256 maxBTCAssetDepegBps;
        uint256 collateralWarningCRBps;
        bool btcYieldPaused;
        bool initialized;
    }

    /// @notice Per-sleeve BTC risk and limit configuration.
    /// @param riskClass BTC sleeve risk category used by preview checks and reporting.
    /// @param enabled Whether the sleeve can pass BTC allocation previews.
    /// @param sleeveCapBps Sleeve-specific cap as a share of accounted BTC.
    /// @param assetDepegBps Observed or configured depeg for the sleeve's BTC-correlated asset.
    /// @param withdrawalDelaySeconds Expected delay before BTC principal can return to idle reserve.
    struct BTCSleeveConfig {
        BTCSleeveRiskClass riskClass;
        bool enabled;
        uint256 sleeveCapBps;
        uint256 assetDepegBps;
        uint256 withdrawalDelaySeconds;
    }

    /// @notice Read-only BTC allocation decision used by reporting and advisory surfaces.
    /// @param allowed Whether the allocation passes current BTC reserve policy.
    /// @param reason Machine-readable decision reason.
    /// @param availableBTC Idle BTC available above the minimum idle reserve.
    /// @param projectedYieldActiveBTC Yield-active BTC after the proposed allocation.
    /// @param requiredApproval Whether multisig-level policy approval is required before execution.
    struct BTCAllocationPreview {
        bool allowed;
        BTCAllocationDecisionCode reason;
        uint256 availableBTC;
        uint256 projectedYieldActiveBTC;
        bool requiredApproval;
    }

    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when BTC reserve policy is configured for a treasury.
    /// @param treasury Treasury Account governed by the policy.
    /// @param actor Treasury admin configuring the policy.
    /// @param minIdleBTCReserve Minimum idle BTC reserve that must remain unallocated.
    /// @param emergencyBTCReserve Required emergency BTC reserve bucket.
    /// @param maxYieldBTCBps Aggregate BTC yield-active exposure cap.
    /// @param maxPerSleeveBTCBps Per-sleeve BTC exposure cap.
    /// @param maxDirectionalBTCBps Directional BTC LP exposure cap.
    /// @param maxBTCAssetDepegBps Maximum tolerated BTC-correlated asset depeg.
    /// @param collateralWarningCRBps Collateral ratio warning threshold for BTC yield previews.
    /// @param btcYieldPaused Whether BTC yield previews are paused.
    event BTCReservePolicyConfigured(
        address indexed treasury,
        address indexed actor,
        uint256 minIdleBTCReserve,
        uint256 emergencyBTCReserve,
        uint256 maxYieldBTCBps,
        uint256 maxPerSleeveBTCBps,
        uint256 maxDirectionalBTCBps,
        uint256 maxBTCAssetDepegBps,
        uint256 collateralWarningCRBps,
        bool btcYieldPaused
    );
    /// @notice Emitted when BTC reserve bucket accounting is updated.
    /// @param treasury Treasury Account whose BTC buckets changed.
    /// @param actor Treasury admin updating the buckets.
    /// @param idleBTCReserve BTC held idle in treasury reserve.
    /// @param collateralBTC BTC reported as Mezo collateral.
    /// @param emergencyBTCReserve BTC tagged for emergency reserve.
    /// @param yieldActiveBTC BTC reported as active in BTC-denominated sleeves.
    /// @param pendingWithdrawBTC BTC pending withdrawal from BTC-denominated sleeves.
    event BTCReserveBucketsUpdated(
        address indexed treasury,
        address indexed actor,
        uint256 idleBTCReserve,
        uint256 collateralBTC,
        uint256 emergencyBTCReserve,
        uint256 yieldActiveBTC,
        uint256 pendingWithdrawBTC
    );
    /// @notice Emitted when a BTC sleeve candidate is configured.
    /// @param treasury Treasury Account whose sleeve policy changed.
    /// @param sleeve BTC sleeve candidate being configured.
    /// @param actor Treasury admin configuring the sleeve.
    /// @param riskClass Risk category assigned to the sleeve.
    /// @param enabled Whether the sleeve can pass BTC allocation previews.
    /// @param sleeveCapBps Sleeve-specific cap as a share of accounted BTC.
    /// @param assetDepegBps Observed or configured BTC-correlated asset depeg.
    /// @param withdrawalDelaySeconds Expected withdrawal delay for the sleeve.
    event BTCSleeveConfigured(
        address indexed treasury,
        address indexed sleeve,
        address indexed actor,
        BTCSleeveRiskClass riskClass,
        bool enabled,
        uint256 sleeveCapBps,
        uint256 assetDepegBps,
        uint256 withdrawalDelaySeconds
    );
    /// @notice Emitted when reported BTC exposure for a sleeve is updated.
    /// @param treasury Treasury Account whose sleeve exposure changed.
    /// @param sleeve BTC sleeve whose exposure changed.
    /// @param actor Treasury admin updating exposure.
    /// @param exposureBTC BTC-denominated sleeve exposure.
    event BTCSleeveExposureUpdated(
        address indexed treasury, address indexed sleeve, address indexed actor, uint256 exposureBTC
    );
    /// @notice Emitted when aggregate directional BTC exposure is updated.
    /// @param treasury Treasury Account whose directional exposure changed.
    /// @param actor Treasury admin updating exposure.
    /// @param directionalExposureBTC BTC-denominated directional LP exposure.
    event BTCDirectionalExposureUpdated(
        address indexed treasury, address indexed actor, uint256 directionalExposureBTC
    );
    /// @notice Emitted when an actor records a BTC allocation preview for audit/reporting.
    /// @param treasury Treasury Account being evaluated.
    /// @param sleeve BTC sleeve candidate being evaluated.
    /// @param actor Treasury actor recording the preview.
    /// @param btcAmount Proposed BTC-denominated allocation amount.
    /// @param allowed Whether the preview passed.
    /// @param reason Machine-readable preview reason.
    /// @param availableBTC Idle BTC available above reserve floor.
    /// @param projectedYieldActiveBTC Yield-active BTC after the proposed allocation.
    /// @param requiredApproval Whether multisig-level approval is required before execution.
    event BTCAllocationPreviewed(
        address indexed treasury,
        address indexed sleeve,
        address indexed actor,
        uint256 btcAmount,
        bool allowed,
        BTCAllocationDecisionCode reason,
        uint256 availableBTC,
        uint256 projectedYieldActiveBTC,
        bool requiredApproval
    );
    /// @notice Emitted when a recorded BTC allocation preview is blocked.
    /// @param treasury Treasury Account being evaluated.
    /// @param sleeve BTC sleeve candidate being evaluated.
    /// @param btcAmount Proposed BTC-denominated allocation amount.
    /// @param reason Machine-readable block reason.
    /// @param availableBTC Idle BTC available above reserve floor.
    event BTCYieldAllocationBlocked(
        address indexed treasury,
        address indexed sleeve,
        uint256 btcAmount,
        BTCAllocationDecisionCode reason,
        uint256 availableBTC
    );
    /// @notice Emitted when a recorded BTC allocation preview passes policy.
    /// @param treasury Treasury Account being evaluated.
    /// @param sleeve BTC sleeve candidate being evaluated.
    /// @param btcAmount Proposed BTC-denominated allocation amount.
    /// @param projectedYieldActiveBTC Yield-active BTC after the proposed allocation.
    /// @param requiredApproval Whether multisig-level approval is required before execution.
    event BTCYieldAllocationApproved(
        address indexed treasury,
        address indexed sleeve,
        uint256 btcAmount,
        uint256 projectedYieldActiveBTC,
        bool requiredApproval
    );

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Reverts when a required address is zero.
    /// @param value Invalid address value.
    error InvalidAddress(address value);
    /// @notice Reverts when a treasury has not been initialized in the MUSD policy engine.
    /// @param treasury Treasury Account being checked.
    error InvalidAccount(address treasury);
    /// @notice Reverts when a basis-point value exceeds 10,000.
    /// @param value Invalid basis-point value.
    error InvalidBasisPoints(uint256 value);
    /// @notice Reverts when a BTC sleeve address is zero.
    /// @param sleeve Invalid sleeve address.
    error InvalidSleeve(address sleeve);
    /// @notice Reverts when an actor lacks authority for the requested BTC policy action.
    /// @param treasury Treasury Account being protected.
    /// @param actor Caller attempting the action.
    error UnauthorizedActor(address treasury, address actor);

    // =============================================================
    // Storage
    // =============================================================

    /// @notice TreasuryOS MUSD policy engine used for treasury admin/operator/approver authority.
    ITreasuryPolicyEngine public immutable treasuryPolicyEngine;
    /// @notice BTC reserve policy stored per Treasury Account.
    mapping(address treasury => BTCReservePolicyConfig policy) public reservePolicies;
    /// @notice BTC reserve bucket accounting stored per Treasury Account.
    mapping(address treasury => BTCReserveBuckets buckets) public reserveBuckets;
    /// @notice BTC sleeve risk configuration stored per Treasury Account and sleeve.
    mapping(address treasury => mapping(address sleeve => BTCSleeveConfig config)) public btcSleeves;
    /// @notice Reported BTC-denominated exposure per Treasury Account and sleeve.
    mapping(address treasury => mapping(address sleeve => uint256 exposureBTC)) public btcSleeveExposureBTC;
    /// @notice Aggregate directional BTC exposure per Treasury Account.
    mapping(address treasury => uint256 exposureBTC) public btcDirectionalExposureBTC;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _treasuryPolicyEngine Existing TreasuryOS policy engine used for authority checks.
    constructor(ITreasuryPolicyEngine _treasuryPolicyEngine) {
        require(address(_treasuryPolicyEngine) != address(0), InvalidAddress(address(_treasuryPolicyEngine)));
        treasuryPolicyEngine = _treasuryPolicyEngine;
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Configures BTC-denominated reserve policy for a Treasury Account.
    /// @param _treasury Treasury Account whose BTC reserve policy is being configured.
    /// @param _config BTC reserve policy parameters.
    function configureBTCReservePolicy(address _treasury, BTCReservePolicyConfig calldata _config) external {
        _requireTreasuryAdmin(_treasury, msg.sender);
        _requireBps(_config.maxYieldBTCBps);
        _requireBps(_config.maxPerSleeveBTCBps);
        _requireBps(_config.maxDirectionalBTCBps);
        _requireBps(_config.maxBTCAssetDepegBps);

        BTCReservePolicyConfig memory _stored = _config;
        _stored.initialized = true;
        reservePolicies[_treasury] = _stored;

        emit BTCReservePolicyConfigured(
            _treasury,
            msg.sender,
            _stored.minIdleBTCReserve,
            _stored.emergencyBTCReserve,
            _stored.maxYieldBTCBps,
            _stored.maxPerSleeveBTCBps,
            _stored.maxDirectionalBTCBps,
            _stored.maxBTCAssetDepegBps,
            _stored.collateralWarningCRBps,
            _stored.btcYieldPaused
        );
    }

    /// @notice Updates BTC bucket accounting for a Treasury Account.
    /// @dev This is reporting/policy state only and does not custody or transfer BTC.
    /// @param _treasury Treasury Account whose BTC buckets are being updated.
    /// @param _buckets Updated BTC bucket values.
    function updateBTCReserveBuckets(address _treasury, BTCReserveBuckets calldata _buckets) external {
        _requireTreasuryAdmin(_treasury, msg.sender);

        reserveBuckets[_treasury] = _buckets;

        emit BTCReserveBucketsUpdated(
            _treasury,
            msg.sender,
            _buckets.idleBTCReserve,
            _buckets.collateralBTC,
            _buckets.emergencyBTCReserve,
            _buckets.yieldActiveBTC,
            _buckets.pendingWithdrawBTC
        );
    }

    /// @notice Configures a BTC-denominated sleeve candidate for preview and reporting.
    /// @param _treasury Treasury Account whose sleeve policy is being updated.
    /// @param _sleeve BTC sleeve candidate.
    /// @param _config Sleeve risk, cap, depeg, and withdrawal metadata.
    function configureBTCSleeve(address _treasury, address _sleeve, BTCSleeveConfig calldata _config) external {
        _requireTreasuryAdmin(_treasury, msg.sender);
        require(_sleeve != address(0), InvalidSleeve(_sleeve));
        _requireBps(_config.sleeveCapBps);
        _requireBps(_config.assetDepegBps);

        btcSleeves[_treasury][_sleeve] = _config;

        emit BTCSleeveConfigured(
            _treasury,
            _sleeve,
            msg.sender,
            _config.riskClass,
            _config.enabled,
            _config.sleeveCapBps,
            _config.assetDepegBps,
            _config.withdrawalDelaySeconds
        );
    }

    /// @notice Updates reported BTC-denominated exposure for a sleeve.
    /// @param _treasury Treasury Account whose exposure is being updated.
    /// @param _sleeve BTC sleeve whose exposure is being updated.
    /// @param _exposureBTC BTC-denominated exposure amount.
    function updateBTCSleeveExposure(address _treasury, address _sleeve, uint256 _exposureBTC) external {
        _requireTreasuryAdmin(_treasury, msg.sender);
        require(_sleeve != address(0), InvalidSleeve(_sleeve));

        btcSleeveExposureBTC[_treasury][_sleeve] = _exposureBTC;

        emit BTCSleeveExposureUpdated(_treasury, _sleeve, msg.sender, _exposureBTC);
    }

    /// @notice Updates aggregate directional BTC LP exposure for a Treasury Account.
    /// @param _treasury Treasury Account whose directional exposure is being updated.
    /// @param _directionalExposureBTC BTC-denominated directional exposure amount.
    function updateBTCDirectionalExposure(address _treasury, uint256 _directionalExposureBTC) external {
        _requireTreasuryAdmin(_treasury, msg.sender);

        btcDirectionalExposureBTC[_treasury] = _directionalExposureBTC;

        emit BTCDirectionalExposureUpdated(_treasury, msg.sender, _directionalExposureBTC);
    }

    /// @notice Records a BTC allocation preview and emits indexable allow/block events.
    /// @dev This does not execute BTC allocation. It is an audit trail for advisory and multisig review flows.
    /// @param _treasury Treasury Account being evaluated.
    /// @param _sleeve BTC sleeve candidate being evaluated.
    /// @param _btcAmount Proposed BTC-denominated allocation amount.
    /// @return preview Structured preview decision.
    function recordBTCAllocationPreview(address _treasury, address _sleeve, uint256 _btcAmount)
        external
        returns (BTCAllocationPreview memory preview)
    {
        _requireTreasuryActor(_treasury, msg.sender);

        preview = previewBTCAllocation(_treasury, _sleeve, _btcAmount);

        emit BTCAllocationPreviewed(
            _treasury,
            _sleeve,
            msg.sender,
            _btcAmount,
            preview.allowed,
            preview.reason,
            preview.availableBTC,
            preview.projectedYieldActiveBTC,
            preview.requiredApproval
        );

        if (preview.allowed) {
            emit BTCYieldAllocationApproved(
                _treasury, _sleeve, _btcAmount, preview.projectedYieldActiveBTC, preview.requiredApproval
            );
        } else {
            emit BTCYieldAllocationBlocked(_treasury, _sleeve, _btcAmount, preview.reason, preview.availableBTC);
        }
    }

    // =============================================================
    // View Functions
    // =============================================================

    /// @notice Previews whether a BTC-denominated sleeve allocation would pass policy.
    /// @param _treasury Treasury Account being evaluated.
    /// @param _sleeve BTC sleeve candidate being evaluated.
    /// @param _btcAmount Proposed BTC-denominated allocation amount.
    /// @return preview Structured preview decision.
    function previewBTCAllocation(address _treasury, address _sleeve, uint256 _btcAmount)
        public
        view
        returns (BTCAllocationPreview memory preview)
    {
        BTCReserveBuckets memory _buckets = reserveBuckets[_treasury];

        preview.availableBTC = availableBTCForYield(_treasury);
        preview.projectedYieldActiveBTC = _buckets.yieldActiveBTC + _btcAmount;
        preview.requiredApproval = _btcAmount > 0;
        preview.reason = _previewReason(_treasury, _sleeve, _btcAmount, preview);
        preview.allowed = preview.reason == BTCAllocationDecisionCode.Allowed;
    }

    /// @notice Returns all BTC accounted across reserve, collateral, active yield, and pending-withdraw buckets.
    /// @param _treasury Treasury Account being queried.
    /// @return Total BTC-denominated amount represented by configured buckets.
    function totalAccountedBTC(address _treasury) public view returns (uint256) {
        BTCReserveBuckets memory _buckets = reserveBuckets[_treasury];
        return _buckets.idleBTCReserve + _buckets.collateralBTC + _buckets.emergencyBTCReserve + _buckets.yieldActiveBTC
            + _buckets.pendingWithdrawBTC;
    }

    /// @notice Returns idle BTC above the minimum idle reserve floor.
    /// @param _treasury Treasury Account being queried.
    /// @return BTC amount available for yield planning before sleeve caps and risk checks.
    function availableBTCForYield(address _treasury) public view returns (uint256) {
        BTCReservePolicyConfig memory _policy = reservePolicies[_treasury];
        BTCReserveBuckets memory _buckets = reserveBuckets[_treasury];

        if (_buckets.idleBTCReserve <= _policy.minIdleBTCReserve) {
            return 0;
        }

        return _buckets.idleBTCReserve - _policy.minIdleBTCReserve;
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Computes the first policy reason for a BTC allocation preview.
    /// @param _treasury Treasury Account being evaluated.
    /// @param _sleeve BTC sleeve candidate being evaluated.
    /// @param _btcAmount Proposed BTC-denominated allocation amount.
    /// @param _preview Partially prepared preview with available/projected BTC fields.
    /// @return Machine-readable preview reason.
    function _previewReason(
        address _treasury,
        address _sleeve,
        uint256 _btcAmount,
        BTCAllocationPreview memory _preview
    ) internal view returns (BTCAllocationDecisionCode) {
        BTCReservePolicyConfig storage _policy = reservePolicies[_treasury];
        BTCReserveBuckets storage _buckets = reserveBuckets[_treasury];
        BTCSleeveConfig storage _sleeveConfig = btcSleeves[_treasury][_sleeve];

        if (!_policy.initialized) {
            return BTCAllocationDecisionCode.PolicyNotConfigured;
        }
        if (_policy.btcYieldPaused) return BTCAllocationDecisionCode.YieldPaused;
        if (_btcAmount == 0) return BTCAllocationDecisionCode.ZeroAmount;
        if (_sleeve == address(0)) return BTCAllocationDecisionCode.InvalidSleeve;
        if (!_sleeveConfig.enabled || _sleeveConfig.riskClass == BTCSleeveRiskClass.DISABLED) {
            return BTCAllocationDecisionCode.SleeveDisabled;
        }
        if (_sleeveConfig.riskClass == BTCSleeveRiskClass.SPECULATIVE) {
            return BTCAllocationDecisionCode.SpeculativeDisabled;
        }
        if (_buckets.emergencyBTCReserve < _policy.emergencyBTCReserve) {
            return BTCAllocationDecisionCode.EmergencyReserveShortfall;
        }
        if (_preview.availableBTC < _btcAmount) {
            return BTCAllocationDecisionCode.InsufficientIdleBTCReserve;
        }

        BTCAllocationDecisionCode _capReason =
            _previewCapReason(_treasury, _sleeve, _btcAmount, _preview.projectedYieldActiveBTC);
        if (_capReason != BTCAllocationDecisionCode.Allowed) return _capReason;

        (bool _hasCollateralRatio, uint256 _collateralRatioBps) = _tryCollateralRatio(_treasury);
        if (
            _policy.collateralWarningCRBps > 0 && _hasCollateralRatio
                && _collateralRatioBps < _policy.collateralWarningCRBps
        ) {
            return BTCAllocationDecisionCode.CollateralHealthWarning;
        }

        return BTCAllocationDecisionCode.Allowed;
    }

    /// @notice Computes aggregate, sleeve-level, directional, and depeg cap failures.
    /// @param _treasury Treasury Account being evaluated.
    /// @param _sleeve BTC sleeve candidate being evaluated.
    /// @param _btcAmount Proposed BTC-denominated allocation amount.
    /// @param _projectedYieldActiveBTC Yield-active BTC after the proposed allocation.
    /// @return Machine-readable cap decision reason.
    function _previewCapReason(address _treasury, address _sleeve, uint256 _btcAmount, uint256 _projectedYieldActiveBTC)
        internal
        view
        returns (BTCAllocationDecisionCode)
    {
        BTCReservePolicyConfig storage _policy = reservePolicies[_treasury];
        BTCSleeveConfig storage _sleeveConfig = btcSleeves[_treasury][_sleeve];

        uint256 _totalAccountedBTC = totalAccountedBTC(_treasury);
        if (_totalAccountedBTC == 0) return BTCAllocationDecisionCode.NoAccountedBTC;

        if (_projectedYieldActiveBTC > _capAmount(_totalAccountedBTC, _policy.maxYieldBTCBps)) {
            return BTCAllocationDecisionCode.TotalYieldCapExceeded;
        }

        uint256 _perSleeveCap =
            _capAmount(_totalAccountedBTC, _min(_policy.maxPerSleeveBTCBps, _sleeveConfig.sleeveCapBps));
        if (btcSleeveExposureBTC[_treasury][_sleeve] + _btcAmount > _perSleeveCap) {
            return BTCAllocationDecisionCode.PerSleeveCapExceeded;
        }

        if (_sleeveConfig.riskClass == BTCSleeveRiskClass.BTC_DIRECTIONAL_LP) {
            uint256 _directionalCap = _capAmount(_totalAccountedBTC, _policy.maxDirectionalBTCBps);
            if (btcDirectionalExposureBTC[_treasury] + _btcAmount > _directionalCap) {
                return BTCAllocationDecisionCode.DirectionalCapExceeded;
            }
        }

        if (_sleeveConfig.assetDepegBps > _policy.maxBTCAssetDepegBps) {
            return BTCAllocationDecisionCode.AssetDepegExceeded;
        }

        return BTCAllocationDecisionCode.Allowed;
    }

    /// @notice Validates that an actor can update BTC reserve or sleeve policy.
    /// @param _treasury Treasury Account being protected.
    /// @param _actor Caller attempting the update.
    function _requireTreasuryAdmin(address _treasury, address _actor) internal view {
        (address _treasuryAdmin,,,,,,, bool _initialized) = treasuryPolicyEngine.getAccountPolicy(_treasury);
        require(_initialized, InvalidAccount(_treasury));
        require(_actor == _treasury || _actor == _treasuryAdmin, UnauthorizedActor(_treasury, _actor));
    }

    /// @notice Validates that an actor can record a BTC allocation preview.
    /// @param _treasury Treasury Account being protected.
    /// @param _actor Caller attempting to record the preview.
    function _requireTreasuryActor(address _treasury, address _actor) internal view {
        (address _treasuryAdmin, address _operator, address _approver,,,,, bool _initialized) =
            treasuryPolicyEngine.getAccountPolicy(_treasury);
        require(_initialized, InvalidAccount(_treasury));
        require(
            _actor == _treasury || _actor == _treasuryAdmin || _actor == _operator || _actor == _approver,
            UnauthorizedActor(_treasury, _actor)
        );
    }

    /// @notice Validates a basis-point value.
    /// @param _value Basis-point value being checked.
    function _requireBps(uint256 _value) internal pure {
        require(_value <= BPS_DENOMINATOR, InvalidBasisPoints(_value));
    }

    /// @notice Attempts to read Treasury Account collateral ratio without making the policy unusable for mocks.
    /// @param _treasury Treasury Account being queried.
    /// @return available Whether a nonzero collateral ratio was returned.
    /// @return ratioBps Collateral ratio in basis points when available.
    function _tryCollateralRatio(address _treasury) internal view returns (bool available, uint256 ratioBps) {
        if (_treasury.code.length == 0) return (false, 0);

        try IBTCTreasuryHealthView(_treasury).collateralRatioBps() returns (uint256 _ratioBps) {
            return (_ratioBps > 0, _ratioBps);
        } catch {
            return (false, 0);
        }
    }

    /// @notice Converts a basis-point cap into an amount.
    /// @param _total Total amount being capped.
    /// @param _capBps Cap in basis points.
    /// @return Amount represented by the cap.
    function _capAmount(uint256 _total, uint256 _capBps) internal pure returns (uint256) {
        return (_total * _capBps) / BPS_DENOMINATOR;
    }

    /// @notice Returns the smaller of two values.
    /// @param _left First value.
    /// @param _right Second value.
    /// @return Smaller value.
    function _min(uint256 _left, uint256 _right) internal pure returns (uint256) {
        return _left < _right ? _left : _right;
    }
}
