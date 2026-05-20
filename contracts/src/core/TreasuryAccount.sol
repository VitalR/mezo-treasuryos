// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAllocationRouterAuthority } from "../interfaces/IAllocationRouterAuthority.sol";
import { IBTCReserveRouterAuthority } from "../interfaces/IBTCReserveRouterAuthority.sol";
import { IAllocationRouter } from "../interfaces/IAllocationRouter.sol";
import { IAllocationRouterView } from "../interfaces/IAllocationRouterView.sol";
import { IBorrowerOperations } from "../interfaces/IBorrowerOperations.sol";
import { IGovernableVariables } from "../interfaces/IGovernableVariables.sol";
import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";
import { IPriceFeed } from "../interfaces/IPriceFeed.sol";
import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";
import { ITigrisStablePoolHandlerMetadata } from "../interfaces/ITigrisStablePoolHandlerMetadata.sol";
import { ITroveManager } from "../interfaces/ITroveManager.sol";

/// @title TreasuryAccount
/// @notice Client-isolated treasury operating boundary for Mezo position management and governed MUSD allocation.
contract TreasuryAccount is Ownable2Step {
    using SafeERC20 for IERC20;

    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when the connected Mezo borrower operations contract is updated.
    event BorrowerOperationsUpdated(address indexed borrowerOperations);
    /// @notice Emitted when the trusted allocation router is updated.
    event AllocationRouterUpdated(address indexed allocationRouter);
    /// @notice Emitted when the trusted BTC reserve router is updated.
    event BTCReserveRouterUpdated(address indexed btcReserveRouter);
    /// @notice Emitted when Treasury Account ownership is finalized and synced into policy state.
    event TreasuryAdminSynced(address indexed previousTreasuryAdmin, address indexed newTreasuryAdmin);
    /// @notice Emitted when a Mezo position is opened for this Treasury Account.
    event PositionOpened(
        uint256 collateralDeposited,
        uint256 musdBorrowed,
        uint256 idleMUSDAfter,
        uint256 positionCollateralAfter,
        uint256 positionDebtAfter
    );
    /// @notice Emitted when collateral is added to the Mezo position.
    event CollateralDeposited(uint256 amount, uint256 positionCollateralAfter);
    /// @notice Emitted when accounted idle BTC reserve is moved into active Mezo collateral.
    event IdleBTCAddedToCollateral(
        address indexed actor, uint256 amount, uint256 idleBTCAfter, uint256 positionCollateralAfter
    );
    /// @notice Emitted when collateral is withdrawn from the Mezo position back into Treasury Account custody.
    event CollateralWithdrawn(uint256 amount, uint256 idleBTCAfter, uint256 positionCollateralAfter);
    /// @notice Emitted when additional MUSD debt is drawn from the Mezo position.
    event DebtDrawn(uint256 amount, uint256 idleMUSDAfter, uint256 positionDebtAfter);
    /// @notice Emitted when MUSD debt is repaid from idle treasury balance.
    event DebtRepaid(uint256 amount, uint256 idleMUSDAfter, uint256 positionDebtAfter);
    /// @notice Emitted when the Mezo position is adjusted through the generic adjust flow.
    event PositionAdjusted(
        uint256 collateralDeposited,
        uint256 collateralWithdrawn,
        uint256 debtChange,
        bool debtIncreased,
        uint256 idleMUSDAfter,
        uint256 idleBTCAfter,
        uint256 positionCollateralAfter,
        uint256 positionDebtAfter
    );
    /// @notice Emitted when the Mezo position is fully closed.
    event PositionClosed(
        uint256 collateralReleased, uint256 debtRepaidToClose, uint256 idleBTCAfter, uint256 idleMUSDAfter
    );
    /// @notice Emitted when idle MUSD is allocated to an approved destination.
    event AllocationExecuted(
        address indexed destination, uint256 amount, uint256 idleBalanceAfter, uint256 allocationAfter
    );
    /// @notice Emitted when deployed MUSD is withdrawn back into the idle treasury balance.
    event WithdrawalExecuted(
        address indexed destination, uint256 amount, uint256 idleBalanceAfter, uint256 allocationAfter
    );
    /// @notice Emitted when yield is claimed from a treasury destination back into idle treasury balance.
    event YieldClaimedFromDestination(address indexed destination, uint256 amount, uint256 idleBalanceAfter);
    /// @notice Emitted when MUSD is funded back into idle treasury balance.
    event IdleMUSDFunded(address indexed funder, uint256 amount, uint256 idleBalanceAfter);
    /// @notice Emitted when BTC is explicitly funded into idle treasury reserve accounting.
    event IdleBTCFunded(address indexed funder, uint256 amount, uint256 idleBTCAfter);
    /// @notice Emitted when idle BTC reserve is allocated into a BTC-denominated sleeve.
    event BTCAllocationExecuted(
        address indexed actor,
        address indexed sleeve,
        uint256 amount,
        uint256 idleBTCAfter,
        uint256 sleevePrincipalAfter
    );
    /// @notice Emitted when BTC-denominated sleeve principal is settled back to idle BTC reserve accounting.
    event BTCWithdrawalSettled(
        address indexed actor,
        address indexed sleeve,
        uint256 principalReduced,
        uint256 idleBTCIncrease,
        uint256 idleBTCAfter,
        uint256 sleevePrincipalAfter
    );
    /// @notice Emitted when idle MUSD is disbursed to an external operating recipient.
    event TreasuryDisbursed(address indexed actor, address indexed recipient, uint256 amount, uint256 idleBalanceAfter);
    /// @notice Emitted when a destination handler settles a routed withdrawal with explicit idle-balance proceeds.
    event WithdrawalSettledFromDestination(
        address indexed destination,
        uint256 allocationAmount,
        uint256 idleMUSDIncrease,
        uint256 idleBalanceAfter,
        uint256 allocationAfter
    );
    /// @notice Emitted when a treasury workflow restores the idle liquidity buffer from a sleeve.
    event LiquidityBufferRestored(
        address indexed actor,
        address indexed destination,
        uint256 requestedMaxAmount,
        uint256 shortfall,
        uint256 restoredAmount,
        uint256 idleBalanceAfter
    );
    /// @notice Emitted when a treasury workflow unwinds a sleeve and repays debt in one bounded operation.
    event SleeveUnwoundAndDebtRepaid(
        address indexed actor,
        address indexed destination,
        uint256 requestedWithdrawAmount,
        uint256 actualWithdrawAmount,
        uint256 requestedRepayAmount,
        uint256 actualRepaidAmount,
        uint256 idleBalanceAfter,
        uint256 positionDebtAfter
    );

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when the allocation router address is zero.
    /// @param allocationRouter Invalid allocation router address.
    error InvalidAllocationRouter(address allocationRouter);
    /// @notice Raised when the BTC reserve router address is zero.
    /// @param btcReserveRouter Invalid BTC reserve router address.
    error InvalidBTCReserveRouter(address btcReserveRouter);
    /// @notice Raised when a required amount is zero or otherwise invalid.
    /// @param amount Invalid amount value.
    error InvalidAmount(uint256 amount);
    /// @notice Raised when the borrower operations address is zero.
    /// @param borrowerOperations Invalid borrower operations address.
    error InvalidBorrowerOperations(address borrowerOperations);
    /// @notice Raised when the MUSD token address is zero.
    /// @param musdToken Invalid MUSD token address.
    error InvalidMUSDToken(address musdToken);
    /// @notice Raised when the policy engine address is zero.
    /// @param policyEngine Invalid policy engine address.
    error InvalidPolicyEngine(address policyEngine);
    /// @notice Raised when a generic trove adjustment request is internally inconsistent.
    error InvalidPositionAdjustment();
    /// @notice Raised when a token address is zero.
    /// @param token Invalid token address.
    error InvalidToken(address token);
    /// @notice Raised when an external execution target is zero.
    /// @param target Invalid execution target.
    error InvalidExecutionTarget(address target);
    /// @notice Raised when an allowance spender address is zero.
    /// @param spender Invalid spender address.
    error InvalidSpender(address spender);
    /// @notice Raised when a trove-dependent action is attempted without an active position.
    error NoActivePosition();
    /// @notice Raised when a caller other than the pending owner attempts ownership acceptance.
    /// @param caller Caller attempting to accept ownership.
    error NotPendingOwner(address caller);
    /// @notice Raised when a repayment request exceeds the current closeable debt.
    /// @param amount Requested repayment amount.
    /// @param currentCloseDebt Current closeable debt.
    error PositionCloseDebtExceeded(uint256 amount, uint256 currentCloseDebt);
    /// @notice Raised when a collateral withdrawal exceeds the current position collateral.
    /// @param amount Requested collateral withdrawal.
    /// @param currentCollateral Current position collateral.
    error PositionCollateralExceeded(uint256 amount, uint256 currentCollateral);
    /// @notice Raised when a new trove is opened while one is already active.
    error PositionAlreadyOpen();
    /// @notice Raised when a treasury disbursement recipient is invalid.
    /// @param recipient Invalid treasury recipient.
    error InvalidTreasuryRecipient(address recipient);
    /// @notice Raised when a savings destination uses an unexpected yield token.
    /// @param expected Expected MUSD token address.
    /// @param actual Actual vault yield token address.
    error UnsupportedYieldToken(address expected, address actual);
    /// @notice Raised when a workflow requires the allocation router but it is not configured.
    error AllocationRouterNotConfigured();
    /// @notice Raised when a workflow or handler settlement attempts to reduce a destination allocation below zero.
    /// @param destination Destination whose tracked allocation would be overdrawn.
    /// @param amount Requested allocation reduction.
    /// @param currentAllocation Current tracked allocation before reduction.
    error InsufficientDestinationAllocation(address destination, uint256 amount, uint256 currentAllocation);
    /// @notice Raised when a BTC sleeve settlement attempts to reduce principal below zero.
    /// @param sleeve BTC sleeve whose tracked principal would be overdrawn.
    /// @param amount Requested principal reduction.
    /// @param currentPrincipal Current tracked BTC principal before reduction.
    error InsufficientBTCSleevePrincipal(address sleeve, uint256 amount, uint256 currentPrincipal);
    /// @notice Raised when idle BTC accounting is below the requested BTC-principal movement.
    /// @param amount Requested BTC amount.
    /// @param idleBTC Current idle BTC accounting balance.
    error InsufficientIdleBTC(uint256 amount, uint256 idleBTC);
    /// @notice Raised when an account-level caller lacks the required authority.
    /// @param caller Unauthorized caller.
    error UnauthorizedCaller(address caller);
    /// @notice Raised when the clone has already been initialized.
    error AlreadyInitialized();

    // =============================================================
    // Types
    // =============================================================

    /// @notice Protocol-backed treasury position snapshot for service and dashboard consumption.
    /// @param owner Treasury Account owner and admin.
    /// @param borrowerOperations Connected Mezo borrower operations contract.
    /// @param governableVariables Governable variables contract referenced by borrower operations.
    /// @param troveManager Active TroveManager used for protocol position reads.
    /// @param allocationRouter Trusted allocation router for governed deployment flows.
    /// @param idleMUSD Idle MUSD currently held in the treasury boundary.
    /// @param idleBTC Idle BTC currently held in the treasury boundary outside the active trove.
    /// @param positionCollateral BTC collateral currently locked in the Mezo position.
    /// @param positionTotalDebt Full protocol debt for the active position.
    /// @param positionCloseDebt Debt that must be repaid in MUSD to close the active position.
    /// @param positionGasCompensation Gas compensation component embedded in protocol debt.
    /// @param positionActive Whether the Treasury Account currently has an active Mezo position.
    struct TreasuryPositionState {
        address owner;
        address borrowerOperations;
        address governableVariables;
        address troveManager;
        address allocationRouter;
        uint256 idleMUSD;
        uint256 idleBTC;
        uint256 positionCollateral;
        uint256 positionTotalDebt;
        uint256 positionCloseDebt;
        uint256 positionGasCompensation;
        bool positionActive;
    }

    /// @notice Treasury health snapshot used by automation services and dashboard risk views.
    /// @param positionActive Whether the Treasury Account currently has an active Mezo position.
    /// @param priceFeed Active protocol price feed used for treasury health reads.
    /// @param collateralPrice Current BTC collateral price returned by the price feed, scaled by 1e18.
    /// @param collateralValueMUSD Current collateral market value expressed in MUSD terms, scaled by 1e18.
    /// @param positionCollateral BTC collateral currently locked in the Mezo position.
    /// @param positionTotalDebt Full protocol debt for the active position.
    /// @param positionCloseDebt Debt that must be repaid in MUSD to close the position.
    /// @param positionGasCompensation Gas compensation component embedded in protocol debt.
    /// @param collateralRatioBps Current collateral ratio expressed in basis points.
    /// @param warningCollateralRatioBps Treasury-defined warning threshold expressed in basis points.
    /// @param criticalCollateralRatioBps Treasury-defined critical threshold expressed in basis points.
    /// @param warningThresholdPrice Price level at which the position would hit the warning threshold.
    /// @param criticalThresholdPrice Price level at which the position would hit the critical threshold.
    /// @param belowWarningRatio Whether the treasury is currently below the warning threshold.
    /// @param belowCriticalRatio Whether the treasury is currently below the critical threshold.
    /// @param riskDataAvailable Whether price-backed health data is currently available.
    /// @param automationEnabled Whether automation is enabled in policy.
    /// @param paused Whether treasury actions are currently paused.
    struct TreasuryHealthState {
        bool positionActive;
        address priceFeed;
        uint256 collateralPrice;
        uint256 collateralValueMUSD;
        uint256 positionCollateral;
        uint256 positionTotalDebt;
        uint256 positionCloseDebt;
        uint256 positionGasCompensation;
        uint256 collateralRatioBps;
        uint256 warningCollateralRatioBps;
        uint256 criticalCollateralRatioBps;
        uint256 warningThresholdPrice;
        uint256 criticalThresholdPrice;
        bool belowWarningRatio;
        bool belowCriticalRatio;
        bool riskDataAvailable;
        bool automationEnabled;
        bool paused;
    }

    /// @notice Per-destination treasury exposure used in composition snapshots.
    /// @param destination Destination address being reported.
    /// @param approved Whether the destination is approved by treasury policy.
    /// @param allocationCap Maximum allowed deployment for the destination.
    /// @param allocatedMUSD Current MUSD allocated to the destination.
    /// @param remainingCapacity Additional MUSD that can be allocated before the cap is reached.
    /// @param yieldToken Yield token exposed by the destination when supported. Zero for unsupported destination types.
    /// @param pairedToken Paired token exposed by a Tigris pool handler when supported.
    ///        Zero for unsupported destination types.
    /// @param handler Registered allocation handler for the destination when one exists.
    /// @param receiptToken Receipt token address held by the Treasury Account for the destination when supported.
    ///        Zero for unsupported destination types.
    /// @param receiptBalance Current destination receipt-token balance held by the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param claimableYield Current claimable yield exposed by the destination for the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param supportsSavingsRate Whether the destination supports MUSDSavingsRate-compatible reporting.
    /// @param supportsTigrisStablePool Whether the destination is routed by the Tigris pool handler.
    struct DestinationExposure {
        address destination;
        bool approved;
        uint256 allocationCap;
        uint256 allocatedMUSD;
        uint256 remainingCapacity;
        address yieldToken;
        address pairedToken;
        address handler;
        address receiptToken;
        uint256 receiptBalance;
        uint256 claimableYield;
        bool supportsSavingsRate;
        bool supportsTigrisStablePool;
    }

    /// @notice Treasury composition snapshot for service and dashboard consumption.
    /// @param idleMUSD Idle treasury-managed MUSD currently available inside the account.
    /// @param idleBTC Idle BTC currently held outside the active Mezo position.
    /// @param totalAllocatedMUSD Aggregate MUSD deployed across the reported destinations.
    /// @param totalManagedMUSD Total treasury-managed MUSD across idle and reported deployed balances.
    /// @param liquidityBuffer Minimum idle MUSD policy buffer.
    /// @param deployableSurplus Idle MUSD available above the configured liquidity buffer.
    /// @param approvalThreshold Maximum operator-controlled movement amount before approver authority is required.
    /// @param automationEnabled Whether automation is enabled in policy.
    /// @param paused Whether treasury operations are currently paused.
    /// @param exposures Per-destination treasury exposure entries.
    struct TreasuryCompositionState {
        uint256 idleMUSD;
        uint256 idleBTC;
        uint256 totalAllocatedMUSD;
        uint256 totalManagedMUSD;
        uint256 liquidityBuffer;
        uint256 deployableSurplus;
        uint256 approvalThreshold;
        bool automationEnabled;
        bool paused;
        DestinationExposure[] exposures;
    }

    /// @notice Machine-readable reason code for allocation previews.
    enum AllocationDecisionCode {
        Allowed,
        Paused,
        ZeroAmount,
        InvalidDestination,
        NotApprovedDestination,
        UnauthorizedActor,
        ApprovalRequired,
        InsufficientIdleBalance,
        LiquidityBufferBreached,
        AllocationCapExceeded
    }

    /// @notice Read-only allocation decision used by consoles, reporting, and memo generation.
    /// @param allowed Whether the allocation would pass the current account policy.
    /// @param code Machine-readable decision reason.
    /// @param actor Treasury actor being evaluated.
    /// @param destination Sleeve destination being evaluated.
    /// @param amount Requested MUSD allocation amount.
    /// @param idleMUSD Current idle MUSD before allocation.
    /// @param liquidityBuffer Required idle operating buffer.
    /// @param deployableSurplus Idle MUSD above the required operating buffer.
    /// @param approvalThreshold Operator movement threshold before approver/admin authority is needed.
    /// @param currentAllocation Current destination allocation.
    /// @param allocationCap Destination allocation cap.
    /// @param remainingCapacity Remaining destination capacity before this action.
    /// @param nextIdleMUSD Projected idle MUSD after allocation.
    /// @param nextAllocation Projected destination allocation after allocation.
    struct AllocationDecision {
        bool allowed;
        AllocationDecisionCode code;
        address actor;
        address destination;
        uint256 amount;
        uint256 idleMUSD;
        uint256 liquidityBuffer;
        uint256 deployableSurplus;
        uint256 approvalThreshold;
        uint256 currentAllocation;
        uint256 allocationCap;
        uint256 remainingCapacity;
        uint256 nextIdleMUSD;
        uint256 nextAllocation;
    }

    // =============================================================
    // Storage
    // =============================================================

    /// @notice TreasuryOS policy engine enforcing internal treasury controls for this account.
    ITreasuryPolicyEngine public policyEngine;
    /// @notice MUSD token used for debt repayment and treasury destination allocations.
    IERC20 public musdToken;
    /// @notice Connected Mezo borrower operations contract used for position lifecycle calls.
    IBorrowerOperations public borrowerOperations;
    /// @notice Trusted allocation router allowed to orchestrate governed destination flows.
    address public allocationRouter;
    /// @notice Trusted BTC reserve router allowed to orchestrate guarded BTC-denominated sleeve flows.
    address public btcReserveRouter;

    /// @notice Idle treasury-managed MUSD held inside the account and available for operations.
    uint256 public idleMUSD;
    /// @notice Idle BTC held directly by the Treasury Account outside the active Mezo position.
    uint256 public idleBTC;
    /// @notice Deployed MUSD amount tracked per approved destination.
    mapping(address destination => uint256 amount) public destinationAllocations;
    /// @notice BTC principal tracked per BTC-denominated sleeve.
    mapping(address sleeve => uint256 amount) public btcSleevePrincipalAllocations;
    /// @notice Whether this clone has been initialized.
    bool public initialized;

    // =============================================================
    // Constructor
    // =============================================================

    constructor() Ownable(address(this)) { }

    /// @notice Initializes a Treasury Account clone.
    /// @param _owner Treasury administrator and owner for the account.
    /// @param _policyEngine Policy engine enforcing TreasuryOS internal controls.
    /// @param _musdToken MUSD token used by this Treasury Account.
    function initialize(address _owner, ITreasuryPolicyEngine _policyEngine, IERC20 _musdToken) external {
        require(!initialized, AlreadyInitialized());
        require(_owner != address(0), Ownable.OwnableInvalidOwner(_owner));
        require(address(_policyEngine) != address(0), InvalidPolicyEngine(address(_policyEngine)));
        require(address(_musdToken) != address(0), InvalidMUSDToken(address(_musdToken)));

        initialized = true;
        policyEngine = _policyEngine;
        musdToken = _musdToken;
        _transferOwnership(_owner);
    }

    // =============================================================
    // Receive
    // =============================================================

    /// @notice Accepts BTC returned from Mezo position withdrawals and closes.
    receive() external payable { }

    // =============================================================
    // Position Lifecycle
    // =============================================================

    /// @notice Opens a Mezo position owned by this Treasury Account and borrows MUSD into idle treasury balance.
    /// @param _musdAmount Amount of MUSD to draw into the Treasury Account.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint) external payable {
        require(address(borrowerOperations) != address(0), InvalidBorrowerOperations(address(borrowerOperations)));
        require(!positionActive(), PositionAlreadyOpen());

        policyEngine.validateBorrow(address(this), msg.sender, _musdAmount, idleMUSD);
        policyEngine.validateCollateralDeposit(address(this), msg.sender, msg.value);
        policyEngine.validateProjectedPosition(
            address(this), msg.sender, msg.value, _projectedOpenDebt(_musdAmount), collateralPrice()
        );

        borrowerOperations.openTrove{ value: msg.value }(_musdAmount, _upperHint, _lowerHint);

        idleMUSD += _musdAmount;

        (uint256 _positionDebt, uint256 _positionCollateral,) = _getPositionSnapshot();
        emit PositionOpened(msg.value, _musdAmount, idleMUSD, _positionCollateral, _positionDebt);
    }

    /// @notice Adjusts the Mezo position using the protocol-native adjust flow.
    /// @param _collWithdrawal Amount of BTC collateral to withdraw from the position.
    /// @param _debtChange Amount of MUSD debt to change.
    /// @param _isDebtIncrease Whether `_debtChange` increases or decreases debt.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable {
        _requireActivePosition();
        _validatePositionAdjustment(msg.sender, msg.value, _collWithdrawal, _debtChange, _isDebtIncrease);

        borrowerOperations.adjustTrove{ value: msg.value }(
            _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint
        );

        _applyPositionAdjustment(_collWithdrawal, _debtChange, _isDebtIncrease);

        (uint256 _positionDebt, uint256 _positionCollateral,) = _getPositionSnapshot();
        emit PositionAdjusted(
            msg.value,
            _collWithdrawal,
            _debtChange,
            _isDebtIncrease,
            idleMUSD,
            idleBTC,
            _positionCollateral,
            _positionDebt
        );
    }

    /// @notice Adds BTC collateral to the active Mezo position.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function addCollateral(address _upperHint, address _lowerHint) external payable {
        _requireActivePosition();
        policyEngine.validateCollateralDeposit(address(this), msg.sender, msg.value);

        borrowerOperations.addColl{ value: msg.value }(_upperHint, _lowerHint);

        emit CollateralDeposited(msg.value, positionCollateral());
    }

    /// @notice Moves accounted idle BTC reserve into active Mezo collateral.
    /// @param _amount Idle BTC amount to add as collateral.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function addIdleBTCToCollateral(uint256 _amount, address _upperHint, address _lowerHint) external {
        _requireActivePosition();
        require(_amount > 0, InvalidAmount(_amount));
        require(idleBTC >= _amount, InsufficientIdleBTC(_amount, idleBTC));
        require(address(this).balance >= _amount, InsufficientIdleBTC(_amount, address(this).balance));

        policyEngine.validateIdleBTCTopUp(address(this), msg.sender, _amount, idleBTC);

        idleBTC -= _amount;
        borrowerOperations.addColl{ value: _amount }(_upperHint, _lowerHint);

        emit IdleBTCAddedToCollateral(msg.sender, _amount, idleBTC, positionCollateral());
    }

    /// @notice Withdraws BTC collateral from the active Mezo position.
    /// @param _amount Amount of BTC collateral to withdraw.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function withdrawCollateral(uint256 _amount, address _upperHint, address _lowerHint) external {
        _requireActivePosition();

        uint256 _currentCollateral = positionCollateral();
        require(_currentCollateral >= _amount, PositionCollateralExceeded(_amount, _currentCollateral));

        policyEngine.validateCollateralWithdrawal(address(this), msg.sender, _amount);
        policyEngine.validateProjectedPosition(
            address(this), msg.sender, _currentCollateral - _amount, positionTotalDebt(), collateralPrice()
        );

        borrowerOperations.withdrawColl(_amount, _upperHint, _lowerHint);

        idleBTC += _amount;

        emit CollateralWithdrawn(_amount, idleBTC, positionCollateral());
    }

    /// @notice Draws additional MUSD debt from the active Mezo position.
    /// @param _amount Amount of MUSD to draw.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        _requireActivePosition();
        policyEngine.validateBorrow(address(this), msg.sender, _amount, idleMUSD);
        policyEngine.validateProjectedPosition(
            address(this),
            msg.sender,
            positionCollateral(),
            positionTotalDebt() + _amount + _borrowingFee(_amount),
            collateralPrice()
        );

        borrowerOperations.withdrawMUSD(_amount, _upperHint, _lowerHint);

        idleMUSD += _amount;

        emit DebtDrawn(_amount, idleMUSD, positionTotalDebt());
    }

    /// @notice Repays MUSD debt from idle treasury balance.
    /// @param _amount Amount of MUSD to repay.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        _requireActivePosition();

        uint256 _currentCloseDebt = positionCloseDebt();
        require(_currentCloseDebt >= _amount, PositionCloseDebtExceeded(_amount, _currentCloseDebt));

        policyEngine.validateDebtRepayment(address(this), msg.sender, _amount, idleMUSD);

        musdToken.forceApprove(address(borrowerOperations), _amount);
        borrowerOperations.repayMUSD(_amount, _upperHint, _lowerHint);

        idleMUSD -= _amount;

        emit DebtRepaid(_amount, idleMUSD, positionTotalDebt());
    }

    /// @notice Closes the Mezo position and releases all posted collateral back into Treasury Account custody.
    function closeTrove() external {
        _requireActivePosition();

        uint256 _closeDebt = positionCloseDebt();
        uint256 _collateral = positionCollateral();

        policyEngine.validateClosePosition(address(this), msg.sender, idleMUSD, _closeDebt);

        musdToken.forceApprove(address(borrowerOperations), _closeDebt);
        borrowerOperations.closeTrove();

        idleMUSD -= _closeDebt;
        idleBTC += _collateral;

        emit PositionClosed(_collateral, _closeDebt, idleBTC, idleMUSD);
    }

    // =============================================================
    // Treasury Operations
    // =============================================================

    /// @notice Funds idle treasury MUSD so the account can restore working capital or repay debt.
    /// @param _amount Amount of MUSD transferred into the Treasury Account.
    function fundIdleMUSD(uint256 _amount) external {
        require(_amount > 0, InvalidAmount(_amount));

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        idleMUSD += _amount;

        emit IdleMUSDFunded(msg.sender, _amount, idleMUSD);
    }

    /// @notice Funds idle BTC reserve accounting with an explicit payable call.
    /// @dev Plain `receive()` does not update `idleBTC`; use this function when BTC is intentionally added to
    ///      treasury reserve inventory outside the Mezo borrow lifecycle.
    function fundIdleBTC() external payable {
        require(msg.value > 0, InvalidAmount(msg.value));

        idleBTC += msg.value;

        emit IdleBTCFunded(msg.sender, msg.value, idleBTC);
    }

    /// @notice Disburses idle MUSD to an external operating recipient.
    /// @param _recipient Recipient receiving the treasury cash movement.
    /// @param _amount Amount of MUSD being disbursed.
    function disburseMUSD(address _recipient, uint256 _amount) external {
        require(_recipient != address(0), InvalidTreasuryRecipient(_recipient));

        policyEngine.validateDisbursement(address(this), msg.sender, _recipient, _amount, idleMUSD);

        idleMUSD -= _amount;
        musdToken.safeTransfer(_recipient, _amount);

        emit TreasuryDisbursed(msg.sender, _recipient, _amount, idleMUSD);
    }

    /// @notice Restores the configured idle liquidity buffer by unwinding an approved sleeve.
    /// @param _destination Destination being unwound for liquidity restoration.
    /// @param _maxAmount Maximum sleeve allocation amount that may be withdrawn.
    /// @return restoredAmount Actual MUSD restored to idle treasury balance.
    function restoreLiquidityBuffer(address _destination, uint256 _maxAmount)
        external
        returns (uint256 restoredAmount)
    {
        require(_maxAmount > 0, InvalidAmount(_maxAmount));

        (,,, uint256 _liquidityBuffer,,,,) = policyEngine.getAccountPolicy(address(this));
        if (idleMUSD >= _liquidityBuffer) {
            return 0;
        }

        uint256 _shortfall = _liquidityBuffer - idleMUSD;
        uint256 _currentAllocation = destinationAllocations[_destination];
        if (_currentAllocation == 0) {
            return 0;
        }

        uint256 _withdrawAmount = _min(_shortfall, _maxAmount);
        _withdrawAmount = _min(_withdrawAmount, _currentAllocation);
        if (_withdrawAmount == 0) {
            return 0;
        }

        policyEngine.validateBufferRestore(address(this), msg.sender, _destination, _withdrawAmount);

        uint256 _idleMUSDBefore = idleMUSD;
        _requireAllocationRouterConfigured();
        IAllocationRouter(allocationRouter).withdrawFor(address(this), msg.sender, _destination, _withdrawAmount);
        restoredAmount = idleMUSD - _idleMUSDBefore;

        emit LiquidityBufferRestored(msg.sender, _destination, _maxAmount, _shortfall, restoredAmount, idleMUSD);
    }

    /// @notice Unwinds a sleeve and repays debt in one bounded treasury workflow.
    /// @param _destination Destination being unwound.
    /// @param _maxWithdrawAmount Maximum sleeve allocation amount that may be withdrawn.
    /// @param _targetRepayAmount Target MUSD amount to repay after unwind.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    /// @return actualWithdrawAmount Actual MUSD restored to idle treasury balance from the unwind.
    /// @return actualRepaidAmount Actual MUSD repaid against the Mezo position.
    function withdrawFromDestinationAndRepay(
        address _destination,
        uint256 _maxWithdrawAmount,
        uint256 _targetRepayAmount,
        address _upperHint,
        address _lowerHint
    ) external returns (uint256 actualWithdrawAmount, uint256 actualRepaidAmount) {
        _requireActivePosition();
        require(_maxWithdrawAmount > 0, InvalidAmount(_maxWithdrawAmount));
        require(_targetRepayAmount > 0, InvalidAmount(_targetRepayAmount));

        uint256 _currentAllocation = destinationAllocations[_destination];
        if (_currentAllocation == 0) {
            return (0, 0);
        }

        uint256 _plannedWithdrawAmount = _min(_maxWithdrawAmount, _currentAllocation);
        uint256 _plannedRepayAmount = _min(_targetRepayAmount, _plannedWithdrawAmount);
        _plannedRepayAmount = _min(_plannedRepayAmount, positionCloseDebt());
        if (_plannedRepayAmount == 0) {
            return (0, 0);
        }

        policyEngine.validateDeRiskRepayment(address(this), msg.sender, _destination, _plannedRepayAmount);

        uint256 _idleMUSDBefore = idleMUSD;
        _requireAllocationRouterConfigured();
        IAllocationRouter(allocationRouter).withdrawFor(address(this), msg.sender, _destination, _plannedWithdrawAmount);
        actualWithdrawAmount = idleMUSD - _idleMUSDBefore;

        actualRepaidAmount = _min(_plannedRepayAmount, actualWithdrawAmount);
        actualRepaidAmount = _min(actualRepaidAmount, positionCloseDebt());

        if (actualRepaidAmount > 0) {
            _repayDebtUnchecked(actualRepaidAmount, _upperHint, _lowerHint);
        }

        emit SleeveUnwoundAndDebtRepaid(
            msg.sender,
            _destination,
            _maxWithdrawAmount,
            actualWithdrawAmount,
            _targetRepayAmount,
            actualRepaidAmount,
            idleMUSD,
            positionTotalDebt()
        );
    }

    // =============================================================
    // Handler-Scoped Execution
    // =============================================================

    /// @notice Sets token allowance from the Treasury Account for an authorized router handler.
    /// @param _token Token being approved.
    /// @param _spender Spender receiving the allowance.
    /// @param _amount Allowance amount to set.
    function forceApproveTokenFromHandler(address _token, address _spender, uint256 _amount) external {
        _requireAuthorizedAllocationCaller();
        require(_token != address(0), InvalidToken(_token));
        require(_spender != address(0), InvalidSpender(_spender));

        IERC20(_token).forceApprove(_spender, _amount);
    }

    /// @notice Executes an arbitrary external call from the Treasury Account for an authorized router handler.
    /// @param _target External contract being called.
    /// @param _value Native value forwarded with the call.
    /// @param _data Calldata executed against the target.
    /// @return result Raw return data from the external call.
    function executeFromHandler(address _target, uint256 _value, bytes calldata _data)
        external
        returns (bytes memory result)
    {
        _requireAuthorizedAllocationCaller();
        require(_target != address(0), InvalidExecutionTarget(_target));

        (bool _success, bytes memory _result) = _target.call{ value: _value }(_data);
        if (!_success) {
            _revertWithReturnData(_result);
        }

        return _result;
    }

    /// @notice Sets token allowance from the Treasury Account for an authorized BTC reserve handler.
    /// @dev This path is separate from MUSD allocation handlers so BTC-principal actions remain owner/multisig scoped.
    /// @param _token Token being approved.
    /// @param _spender Spender receiving the allowance.
    /// @param _amount Allowance amount to set.
    function forceApproveTokenFromBTCHandler(address _token, address _spender, uint256 _amount) external {
        _requireAuthorizedBTCReserveCaller();
        require(_token != address(0), InvalidToken(_token));
        require(_spender != address(0), InvalidSpender(_spender));

        IERC20(_token).forceApprove(_spender, _amount);
    }

    /// @notice Executes an external call from the Treasury Account for an authorized BTC reserve handler.
    /// @dev Used by guarded BTC handlers so BTC assets and LP receipt tokens remain owned by the Treasury Account.
    /// @param _target External contract being called.
    /// @param _value Native value forwarded with the call.
    /// @param _data Calldata executed against the target.
    /// @return result Raw return data from the external call.
    function executeFromBTCHandler(address _target, uint256 _value, bytes calldata _data)
        external
        returns (bytes memory result)
    {
        _requireAuthorizedBTCReserveCaller();
        require(_target != address(0), InvalidExecutionTarget(_target));

        (bool _success, bytes memory _result) = _target.call{ value: _value }(_data);
        if (!_success) {
            _revertWithReturnData(_result);
        }

        return _result;
    }

    /// @notice Debits idle BTC accounting for a guarded BTC sleeve entry.
    /// @dev Only an authorized BTC reserve handler can call this, and the initiating actor must be the owner. In the
    ///      product path, that owner is expected to be a TreasuryMultisig or external custody/multisig account.
    /// @param _actor Treasury owner/multisig initiating the principal movement.
    /// @param _sleeve BTC sleeve receiving principal exposure.
    /// @param _amount BTC-principal amount being allocated from idle reserve accounting.
    function allocateIdleBTCFromBTCHandler(address _actor, address _sleeve, uint256 _amount) external {
        _requireAuthorizedBTCReserveCaller();
        require(_actor == owner(), UnauthorizedCaller(_actor));
        require(_sleeve != address(0), InvalidExecutionTarget(_sleeve));
        require(_amount > 0, InvalidAmount(_amount));
        require(idleBTC >= _amount, InsufficientIdleBTC(_amount, idleBTC));

        idleBTC -= _amount;
        btcSleevePrincipalAllocations[_sleeve] += _amount;

        emit BTCAllocationExecuted(_actor, _sleeve, _amount, idleBTC, btcSleevePrincipalAllocations[_sleeve]);
    }

    /// @notice Settles BTC-denominated sleeve principal back into idle BTC reserve accounting.
    /// @dev Used for guarded exits and for returning any unused BTC after an LP entry.
    /// @param _actor Treasury owner/multisig initiating the settlement.
    /// @param _sleeve BTC sleeve whose principal accounting is reduced.
    /// @param _principalReduction BTC-principal amount removed from sleeve accounting.
    /// @param _idleBTCIncrease BTC amount credited back to idle reserve accounting.
    function settleBTCWithdrawalFromHandler(
        address _actor,
        address _sleeve,
        uint256 _principalReduction,
        uint256 _idleBTCIncrease
    ) external {
        _requireAuthorizedBTCReserveCaller();
        require(_actor == owner(), UnauthorizedCaller(_actor));
        require(_sleeve != address(0), InvalidExecutionTarget(_sleeve));
        require(_principalReduction > 0 || _idleBTCIncrease > 0, InvalidAmount(0));

        uint256 _currentPrincipal = btcSleevePrincipalAllocations[_sleeve];
        require(
            _currentPrincipal >= _principalReduction,
            InsufficientBTCSleevePrincipal(_sleeve, _principalReduction, _currentPrincipal)
        );

        btcSleevePrincipalAllocations[_sleeve] = _currentPrincipal - _principalReduction;
        idleBTC += _idleBTCIncrease;

        emit BTCWithdrawalSettled(
            _actor, _sleeve, _principalReduction, _idleBTCIncrease, idleBTC, btcSleevePrincipalAllocations[_sleeve]
        );
    }

    /// @notice Deposits idle MUSD into the configured MUSD Savings Rate vault through the trusted adapter flow.
    /// @param _actor Treasury actor on whose behalf the deposit is being performed.
    /// @param _savingsRate Savings Rate destination receiving the principal.
    /// @param _amount Amount of MUSD principal being deposited.
    /// @return mintedShares Amount of sMUSD minted to the Treasury Account.
    function depositIntoSavingsRateFromAdapter(address _actor, address _savingsRate, uint256 _amount)
        external
        returns (uint256 mintedShares)
    {
        _requireAuthorizedAllocationCaller();

        IMUSDSavingsRate savingsRate = IMUSDSavingsRate(_savingsRate);
        _requireSupportedYieldToken(savingsRate);

        uint256 currentAllocation = destinationAllocations[_savingsRate];

        policyEngine.validateAllocate(address(this), _actor, _savingsRate, _amount, idleMUSD, currentAllocation);

        uint256 previousShareBalance = savingsRate.balanceOf(address(this));
        musdToken.forceApprove(_savingsRate, _amount);
        savingsRate.deposit(_amount);
        mintedShares = savingsRate.balanceOf(address(this)) - previousShareBalance;

        idleMUSD -= _amount;
        destinationAllocations[_savingsRate] = currentAllocation + _amount;

        emit AllocationExecuted(_savingsRate, _amount, idleMUSD, destinationAllocations[_savingsRate]);
    }

    /// @notice Withdraws principal from the configured MUSD Savings Rate vault through the trusted adapter flow.
    /// @param _actor Treasury actor on whose behalf the withdrawal is being performed.
    /// @param _savingsRate Savings Rate destination being withdrawn from.
    /// @param _amount Amount of MUSD principal being withdrawn.
    /// @return burnedShares Amount of sMUSD burned from the Treasury Account.
    function withdrawFromSavingsRateFromAdapter(address _actor, address _savingsRate, uint256 _amount)
        external
        returns (uint256 burnedShares)
    {
        _requireAuthorizedAllocationCaller();

        IMUSDSavingsRate savingsRate = IMUSDSavingsRate(_savingsRate);
        _requireSupportedYieldToken(savingsRate);

        uint256 currentAllocation = destinationAllocations[_savingsRate];

        policyEngine.validateWithdraw(address(this), _actor, _savingsRate, _amount, currentAllocation);

        uint256 previousShareBalance = savingsRate.balanceOf(address(this));
        savingsRate.withdraw(_amount);
        burnedShares = previousShareBalance - savingsRate.balanceOf(address(this));

        destinationAllocations[_savingsRate] = currentAllocation - _amount;
        idleMUSD += _amount;

        emit WithdrawalExecuted(_savingsRate, _amount, idleMUSD, destinationAllocations[_savingsRate]);
    }

    /// @notice Withdraws principal from the configured MUSD Savings Rate vault as part of a pre-validated workflow.
    /// @dev Used by high-level treasury workflows that already performed their own bounded policy validation.
    /// @param _actor Treasury actor on whose behalf the workflow withdrawal is being performed.
    /// @param _savingsRate Savings Rate destination being withdrawn from.
    /// @param _amount Amount of MUSD principal being withdrawn.
    /// @return burnedShares Amount of sMUSD burned from the Treasury Account.
    function withdrawFromSavingsRateForWorkflowFromAdapter(address _actor, address _savingsRate, uint256 _amount)
        external
        returns (uint256 burnedShares)
    {
        _requireAuthorizedAllocationCaller();

        IMUSDSavingsRate savingsRate = IMUSDSavingsRate(_savingsRate);
        _requireSupportedYieldToken(savingsRate);

        uint256 currentAllocation = destinationAllocations[_savingsRate];
        require(
            currentAllocation >= _amount, InsufficientDestinationAllocation(_savingsRate, _amount, currentAllocation)
        );

        uint256 previousShareBalance = savingsRate.balanceOf(address(this));
        savingsRate.withdraw(_amount);
        burnedShares = previousShareBalance - savingsRate.balanceOf(address(this));

        destinationAllocations[_savingsRate] = currentAllocation - _amount;
        idleMUSD += _amount;

        emit WithdrawalExecuted(_savingsRate, _amount, idleMUSD, destinationAllocations[_savingsRate]);
        _actor;
    }

    /// @notice Claims accrued yield from the configured MUSD Savings Rate vault through the trusted adapter flow.
    /// @param _actor Treasury actor on whose behalf the yield claim is being performed.
    /// @param _savingsRate Savings Rate destination paying the yield.
    /// @return claimedYield Amount of MUSD yield claimed into idle treasury balance.
    function claimSavingsRateYieldFromAdapter(address _actor, address _savingsRate)
        external
        returns (uint256 claimedYield)
    {
        _requireAuthorizedAllocationCaller();

        IMUSDSavingsRate savingsRate = IMUSDSavingsRate(_savingsRate);
        _requireSupportedYieldToken(savingsRate);

        policyEngine.validateYieldClaim(address(this), _actor);

        claimedYield = savingsRate.claimYield();
        idleMUSD += claimedYield;

        emit YieldClaimedFromDestination(_savingsRate, claimedYield, idleMUSD);
    }

    // =============================================================
    // Direct Allocation Accounting
    // =============================================================

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

    /// @notice Allocates idle MUSD through the configured allocation router on behalf of a treasury actor.
    /// @param _actor Treasury actor on whose behalf the allocation is being performed.
    /// @param _destination Destination receiving funds.
    /// @param _amount Amount being allocated.
    function allocateFromAdapter(address _actor, address _destination, uint256 _amount) external {
        _requireAuthorizedAllocationCaller();

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

    /// @notice Withdraws previously allocated MUSD through the configured allocation router.
    /// @param _actor Treasury actor on whose behalf the withdrawal is being performed.
    /// @param _destination Destination being withdrawn from.
    /// @param _amount Amount being withdrawn.
    function withdrawFromAdapter(address _actor, address _destination, uint256 _amount) external {
        _requireAuthorizedAllocationCaller();

        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateWithdraw(address(this), _actor, _destination, _amount, currentAllocation);

        destinationAllocations[_destination] = currentAllocation - _amount;
        idleMUSD += _amount;

        emit WithdrawalExecuted(_destination, _amount, idleMUSD, destinationAllocations[_destination]);
    }

    /// @notice Settles a handler-routed withdrawal where actual MUSD proceeds can differ from tracked allocation
    ///     reduction.
    /// @param _actor Treasury actor on whose behalf the settlement is being performed.
    /// @param _destination Destination being reduced.
    /// @param _allocationAmount Amount of tracked allocation being reduced.
    /// @param _idleMUSDIncrease Actual MUSD proceeds restored to idle treasury balance.
    function settleWithdrawalFromHandler(
        address _actor,
        address _destination,
        uint256 _allocationAmount,
        uint256 _idleMUSDIncrease
    ) external {
        _requireAuthorizedAllocationCaller();

        uint256 currentAllocation = destinationAllocations[_destination];

        policyEngine.validateWithdrawalSettlement(
            address(this), _actor, _destination, _allocationAmount, currentAllocation
        );

        destinationAllocations[_destination] = currentAllocation - _allocationAmount;
        idleMUSD += _idleMUSDIncrease;

        emit WithdrawalSettledFromDestination(
            _destination, _allocationAmount, _idleMUSDIncrease, idleMUSD, destinationAllocations[_destination]
        );
    }

    /// @notice Settles a handler-routed workflow withdrawal after the outer workflow already validated bounded policy.
    /// @param _actor Treasury actor on whose behalf the workflow settlement is being performed.
    /// @param _destination Destination being reduced.
    /// @param _allocationAmount Amount of tracked allocation being reduced.
    /// @param _idleMUSDIncrease Actual MUSD proceeds restored to idle treasury balance.
    function settleWorkflowWithdrawalFromHandler(
        address _actor,
        address _destination,
        uint256 _allocationAmount,
        uint256 _idleMUSDIncrease
    ) external {
        _requireAuthorizedAllocationCaller();

        uint256 currentAllocation = destinationAllocations[_destination];
        require(
            currentAllocation >= _allocationAmount,
            InsufficientDestinationAllocation(_destination, _allocationAmount, currentAllocation)
        );

        destinationAllocations[_destination] = currentAllocation - _allocationAmount;
        idleMUSD += _idleMUSDIncrease;

        emit WithdrawalSettledFromDestination(
            _destination, _allocationAmount, _idleMUSDIncrease, idleMUSD, destinationAllocations[_destination]
        );
        _actor;
    }

    // =============================================================
    // Administration
    // =============================================================

    /// @notice Updates the paused state of the Treasury Account.
    /// @param _paused New paused state.
    function setPause(bool _paused) external {
        (,, address approver,,,,,) = policyEngine.getAccountPolicy(address(this));
        require(msg.sender == owner() || msg.sender == approver, UnauthorizedCaller(msg.sender));

        policyEngine.setPause(address(this), _paused);
    }

    /// @notice Sets the Mezo borrower operations contract used for position lifecycle management.
    /// @param _borrowerOperations Borrower operations contract for opening and managing the Mezo position.
    function setBorrowerOperations(address _borrowerOperations) external onlyOwner {
        require(_borrowerOperations != address(0), InvalidBorrowerOperations(_borrowerOperations));

        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        emit BorrowerOperationsUpdated(_borrowerOperations);
    }

    /// @notice Sets the trusted allocation router for routed deployment and withdrawal flows.
    /// @param _allocationRouter Allocation router allowed to mutate treasury allocation state.
    function setAllocationRouter(address _allocationRouter) external onlyOwner {
        require(_allocationRouter != address(0), InvalidAllocationRouter(_allocationRouter));

        allocationRouter = _allocationRouter;
        emit AllocationRouterUpdated(_allocationRouter);
    }

    /// @notice Sets the trusted BTC reserve router for guarded BTC-denominated sleeve flows.
    /// @param _btcReserveRouter BTC reserve router allowed to authorize BTC sleeve handlers.
    function setBTCReserveRouter(address _btcReserveRouter) external onlyOwner {
        require(_btcReserveRouter != address(0), InvalidBTCReserveRouter(_btcReserveRouter));

        btcReserveRouter = _btcReserveRouter;
        emit BTCReserveRouterUpdated(_btcReserveRouter);
    }

    /// @notice Finalizes a pending ownership transfer and syncs the policy engine's treasury admin.
    function acceptOwnership() public override {
        require(msg.sender == pendingOwner(), NotPendingOwner(msg.sender));

        address _previousTreasuryAdmin = owner();

        super.acceptOwnership();
        policyEngine.updateTreasuryAdmin(address(this), owner());

        emit TreasuryAdminSynced(_previousTreasuryAdmin, owner());
    }

    // =============================================================
    // View Functions
    // =============================================================

    /// @notice Returns the protocol governable variables contract configured by borrower operations.
    function governableVariables() public view returns (IGovernableVariables) {
        if (address(borrowerOperations) == address(0)) {
            return IGovernableVariables(address(0));
        }

        return borrowerOperations.governableVariables();
    }

    /// @notice Returns the active TroveManager used for protocol-backed position reads.
    function troveManager() public view returns (ITroveManager) {
        IGovernableVariables _governableVariables = governableVariables();
        if (address(_governableVariables) == address(0)) {
            return ITroveManager(address(0));
        }

        return ITroveManager(_governableVariables.troveManager());
    }

    /// @notice Returns the active protocol price feed used for treasury health reads.
    function priceFeed() public view returns (IPriceFeed) {
        IGovernableVariables _governableVariables = governableVariables();
        if (address(_governableVariables) == address(0)) {
            return IPriceFeed(address(0));
        }

        return IPriceFeed(_governableVariables.priceFeed());
    }

    /// @notice Returns the full protocol debt for the active position, including fee, gas compensation, and accrual.
    function positionTotalDebt() public view returns (uint256) {
        (uint256 _positionDebt,,) = _getPositionSnapshot();
        return _positionDebt;
    }

    /// @notice Returns the currently locked collateral for the active position.
    function positionCollateral() public view returns (uint256) {
        (, uint256 _positionCollateral,) = _getPositionSnapshot();
        return _positionCollateral;
    }

    /// @notice Returns the protocol gas compensation attached to the active trove.
    function positionGasCompensation() public view returns (uint256) {
        ITroveManager _troveManager = troveManager();
        if (address(_troveManager) == address(0)) {
            return 0;
        }

        return _troveManager.MUSD_GAS_COMPENSATION();
    }

    /// @notice Returns the MUSD amount that must be available to close the active position.
    function positionCloseDebt() public view returns (uint256) {
        uint256 _positionDebt = positionTotalDebt();
        uint256 _gasCompensation = positionGasCompensation();

        if (_positionDebt <= _gasCompensation) {
            return 0;
        }

        return _positionDebt - _gasCompensation;
    }

    /// @notice Returns whether the Treasury Account currently holds an active Mezo position.
    function positionActive() public view returns (bool) {
        (,, bool _active) = _getPositionSnapshot();
        return _active;
    }

    /// @notice Returns the current collateral price used for TreasuryOS health calculations.
    /// @dev Returns zero when no price feed is configured.
    function collateralPrice() public view returns (uint256) {
        IPriceFeed _priceFeed = priceFeed();
        if (address(_priceFeed) == address(0)) {
            return 0;
        }

        return _priceFeed.fetchPrice();
    }

    /// @notice Returns the current collateral market value of the active position in MUSD terms.
    /// @dev Uses the TreasuryOS collateral price read and returns zero when price data is unavailable.
    function collateralValueMUSD() public view returns (uint256) {
        return _collateralValueMUSD(positionCollateral(), collateralPrice());
    }

    /// @notice Returns the current collateral ratio for the active position in basis points.
    /// @dev Returns zero when the position is inactive or price-backed health data is unavailable.
    function collateralRatioBps() public view returns (uint256) {
        return _collateralRatioBps(positionCollateral(), positionTotalDebt(), collateralPrice());
    }

    /// @notice Returns whether price-backed health data is available for the current treasury position.
    function riskDataAvailable() public view returns (bool) {
        return _riskDataAvailable(positionCollateral(), positionTotalDebt(), collateralPrice());
    }

    /// @notice Returns whether the current collateral ratio is below the configured warning threshold.
    function isBelowWarningRatio() public view returns (bool) {
        (uint256 _warningCollateralRatioBps,) = policyEngine.getAccountRiskPolicy(address(this));

        if (!riskDataAvailable()) {
            return false;
        }

        return collateralRatioBps() < _warningCollateralRatioBps;
    }

    /// @notice Returns whether the current collateral ratio is below the configured critical threshold.
    function isBelowCriticalRatio() public view returns (bool) {
        (, uint256 _criticalCollateralRatioBps) = policyEngine.getAccountRiskPolicy(address(this));

        if (!riskDataAvailable()) {
            return false;
        }

        return collateralRatioBps() < _criticalCollateralRatioBps;
    }

    /// @notice Returns the collateral price at which the current position would reach the warning threshold.
    /// @dev Returns zero when the position is inactive or the threshold cannot be evaluated.
    function warningThresholdPrice() public view returns (uint256) {
        (uint256 _warningCollateralRatioBps,) = policyEngine.getAccountRiskPolicy(address(this));
        return _thresholdPrice(positionCollateral(), positionTotalDebt(), _warningCollateralRatioBps);
    }

    /// @notice Returns the collateral price at which the current position would reach the critical threshold.
    /// @dev Returns zero when the position is inactive or the threshold cannot be evaluated.
    function criticalThresholdPrice() public view returns (uint256) {
        (, uint256 _criticalCollateralRatioBps) = policyEngine.getAccountRiskPolicy(address(this));
        return _thresholdPrice(positionCollateral(), positionTotalDebt(), _criticalCollateralRatioBps);
    }

    /// @notice Returns a consolidated protocol-backed treasury position snapshot.
    function getTreasuryPositionState() external view returns (TreasuryPositionState memory state) {
        ITroveManager _troveManager = troveManager();
        IGovernableVariables _governableVariables = governableVariables();
        (uint256 _positionTotalDebt, uint256 _positionCollateral, bool _positionActive) = _getPositionSnapshot();

        uint256 _positionGasCompensation;
        if (address(_troveManager) != address(0)) {
            _positionGasCompensation = _troveManager.MUSD_GAS_COMPENSATION();
        }

        uint256 _positionCloseDebt;
        if (_positionTotalDebt > _positionGasCompensation) {
            _positionCloseDebt = _positionTotalDebt - _positionGasCompensation;
        }

        state = TreasuryPositionState({
            owner: owner(),
            borrowerOperations: address(borrowerOperations),
            governableVariables: address(_governableVariables),
            troveManager: address(_troveManager),
            allocationRouter: allocationRouter,
            idleMUSD: idleMUSD,
            idleBTC: idleBTC,
            positionCollateral: _positionCollateral,
            positionTotalDebt: _positionTotalDebt,
            positionCloseDebt: _positionCloseDebt,
            positionGasCompensation: _positionGasCompensation,
            positionActive: _positionActive
        });
    }

    /// @notice Returns a consolidated treasury health snapshot for automation and dashboard risk monitoring.
    function getTreasuryHealthState() external view returns (TreasuryHealthState memory state) {
        (uint256 _warningCollateralRatioBps, uint256 _criticalCollateralRatioBps) =
            policyEngine.getAccountRiskPolicy(address(this));
        (,,,,, bool _automationEnabled, bool _paused,) = policyEngine.getAccountPolicy(address(this));

        IPriceFeed _priceFeed = priceFeed();
        uint256 _positionCollateral = positionCollateral();
        uint256 _positionTotalDebt = positionTotalDebt();
        uint256 _positionGasCompensation = positionGasCompensation();
        uint256 _positionCloseDebt = positionCloseDebt();
        uint256 _collateralPrice = collateralPrice();
        uint256 _collateralValue = _collateralValueMUSD(_positionCollateral, _collateralPrice);
        uint256 _collateralRatio = _collateralRatioBps(_positionCollateral, _positionTotalDebt, _collateralPrice);
        bool _riskData = _riskDataAvailable(_positionCollateral, _positionTotalDebt, _collateralPrice);

        state.positionActive = positionActive();
        state.priceFeed = address(_priceFeed);
        state.collateralPrice = _collateralPrice;
        state.collateralValueMUSD = _collateralValue;
        state.positionCollateral = _positionCollateral;
        state.positionTotalDebt = _positionTotalDebt;
        state.positionCloseDebt = _positionCloseDebt;
        state.positionGasCompensation = _positionGasCompensation;
        state.collateralRatioBps = _collateralRatio;
        state.warningCollateralRatioBps = _warningCollateralRatioBps;
        state.criticalCollateralRatioBps = _criticalCollateralRatioBps;
        state.warningThresholdPrice =
            _thresholdPrice(_positionCollateral, _positionTotalDebt, _warningCollateralRatioBps);
        state.criticalThresholdPrice =
            _thresholdPrice(_positionCollateral, _positionTotalDebt, _criticalCollateralRatioBps);
        state.belowWarningRatio = _riskData && _collateralRatio < _warningCollateralRatioBps;
        state.belowCriticalRatio = _riskData && _collateralRatio < _criticalCollateralRatioBps;
        state.riskDataAvailable = _riskData;
        state.automationEnabled = _automationEnabled;
        state.paused = _paused;
    }

    /// @notice Returns treasury composition and destination exposures for the provided destination set.
    /// @param _destinations Destination addresses to include in the composition snapshot.
    function getTreasuryComposition(address[] calldata _destinations)
        external
        view
        returns (TreasuryCompositionState memory state)
    {
        (,,, uint256 _liquidityBuffer, uint256 _approvalThreshold, bool _automationEnabled, bool _paused,) =
            policyEngine.getAccountPolicy(address(this));

        DestinationExposure[] memory _exposures = new DestinationExposure[](_destinations.length);
        uint256 _totalAllocatedMUSD;

        for (uint256 _i = 0; _i < _destinations.length; _i++) {
            (DestinationExposure memory _exposure, uint256 _allocatedMUSD) = _getDestinationExposure(_destinations[_i]);
            _totalAllocatedMUSD += _allocatedMUSD;
            _exposures[_i] = _exposure;
        }

        uint256 _deployableSurplus;
        if (idleMUSD > _liquidityBuffer) {
            _deployableSurplus = idleMUSD - _liquidityBuffer;
        }

        state = TreasuryCompositionState({
            idleMUSD: idleMUSD,
            idleBTC: idleBTC,
            totalAllocatedMUSD: _totalAllocatedMUSD,
            totalManagedMUSD: idleMUSD + _totalAllocatedMUSD,
            liquidityBuffer: _liquidityBuffer,
            deployableSurplus: _deployableSurplus,
            approvalThreshold: _approvalThreshold,
            automationEnabled: _automationEnabled,
            paused: _paused,
            exposures: _exposures
        });
    }

    /// @notice Previews whether an idle-MUSD allocation would pass policy and why.
    /// @dev This mirrors the allocation policy checks without mutating state or replacing enforcement.
    /// @param _actor Treasury actor whose authority should be evaluated.
    /// @param _destination Destination sleeve being evaluated.
    /// @param _amount Requested MUSD allocation amount.
    function previewAllocation(address _actor, address _destination, uint256 _amount)
        external
        view
        returns (AllocationDecision memory decision)
    {
        (
            address _treasuryAdmin,
            address _operator,
            address _approver,
            uint256 _liquidityBuffer,
            uint256 _approvalThreshold,,
            bool _paused,
        ) = policyEngine.getAccountPolicy(address(this));

        decision.actor = _actor;
        decision.destination = _destination;
        decision.amount = _amount;
        decision.idleMUSD = idleMUSD;
        decision.liquidityBuffer = _liquidityBuffer;
        decision.approvalThreshold = _approvalThreshold;
        decision.currentAllocation = destinationAllocations[_destination];
        decision.allocationCap = policyEngine.allocationCap(address(this), _destination);

        if (decision.allocationCap > decision.currentAllocation) {
            decision.remainingCapacity = decision.allocationCap - decision.currentAllocation;
        }

        if (idleMUSD > _liquidityBuffer) {
            decision.deployableSurplus = idleMUSD - _liquidityBuffer;
        }

        if (idleMUSD >= _amount) {
            decision.nextIdleMUSD = idleMUSD - _amount;
        }

        decision.nextAllocation = type(uint256).max;
        if (type(uint256).max - decision.currentAllocation >= _amount) {
            decision.nextAllocation = decision.currentAllocation + _amount;
        }

        decision.code = _previewAllocationCode(decision, _treasuryAdmin, _operator, _approver, _paused);
        decision.allowed = decision.code == AllocationDecisionCode.Allowed;
    }

    /// @notice Evaluates a prepared allocation preview against current policy inputs.
    function _previewAllocationCode(
        AllocationDecision memory _decision,
        address _treasuryAdmin,
        address _operator,
        address _approver,
        bool _paused
    ) internal view returns (AllocationDecisionCode code) {
        if (_paused) {
            return AllocationDecisionCode.Paused;
        }

        if (_decision.amount == 0) {
            return AllocationDecisionCode.ZeroAmount;
        }

        if (_decision.destination == address(0)) {
            return AllocationDecisionCode.InvalidDestination;
        }

        if (!policyEngine.isDestinationApproved(address(this), _decision.destination)) {
            return AllocationDecisionCode.NotApprovedDestination;
        }

        if (_decision.actor != _treasuryAdmin && _decision.actor != _approver && _decision.actor != _operator) {
            return AllocationDecisionCode.UnauthorizedActor;
        }

        if (_decision.actor == _operator && _decision.amount > _decision.approvalThreshold) {
            return AllocationDecisionCode.ApprovalRequired;
        }

        if (_decision.idleMUSD < _decision.amount) {
            return AllocationDecisionCode.InsufficientIdleBalance;
        }

        if (_decision.nextIdleMUSD < _decision.liquidityBuffer) {
            return AllocationDecisionCode.LiquidityBufferBreached;
        }

        if (_decision.nextAllocation > _decision.allocationCap) {
            return AllocationDecisionCode.AllocationCapExceeded;
        }

        return AllocationDecisionCode.Allowed;
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Applies local idle-balance accounting after a protocol-native trove adjustment.
    /// @param _collateralWithdrawal BTC collateral withdrawn back into idle treasury custody.
    /// @param _debtChange MUSD debt change applied by the protocol.
    /// @param _isDebtIncrease Whether the protocol debt change increased or decreased debt.
    function _applyPositionAdjustment(uint256 _collateralWithdrawal, uint256 _debtChange, bool _isDebtIncrease)
        internal
    {
        idleBTC += _collateralWithdrawal;

        if (_debtChange == 0) {
            return;
        }

        if (_isDebtIncrease) {
            idleMUSD += _debtChange;
            return;
        }

        idleMUSD -= _debtChange;
    }

    /// @notice Repays protocol debt without re-running the generic public repayment policy checks.
    /// @param _amount Amount of MUSD being repaid.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function _repayDebtUnchecked(uint256 _amount, address _upperHint, address _lowerHint) internal {
        if (_amount == 0) {
            return;
        }

        musdToken.forceApprove(address(borrowerOperations), _amount);
        borrowerOperations.repayMUSD(_amount, _upperHint, _lowerHint);

        idleMUSD -= _amount;

        emit DebtRepaid(_amount, idleMUSD, positionTotalDebt());
    }

    /// @notice Returns the protocol-backed treasury position snapshot from Mezo state.
    /// @return _positionDebt Full protocol debt for the treasury position.
    /// @return _positionCollateral Current position collateral.
    /// @return _active Whether the treasury currently has an active position.
    function _getPositionSnapshot()
        internal
        view
        returns (uint256 _positionDebt, uint256 _positionCollateral, bool _active)
    {
        ITroveManager _troveManager = troveManager();
        if (address(_troveManager) == address(0)) {
            return (0, 0, false);
        }

        (_positionDebt, _positionCollateral) = _troveManager.getEntireDebtAndColl(address(this));
        _active = _positionDebt > 0 || _positionCollateral > 0;
    }

    /// @notice Returns TreasuryOS exposure metadata for a destination.
    /// @param _destination Destination being inspected.
    /// @return exposure Structured exposure metadata for dashboard and service consumption.
    /// @return allocatedMUSD Current tracked MUSD allocation for the destination.
    function _getDestinationExposure(address _destination)
        internal
        view
        returns (DestinationExposure memory exposure, uint256 allocatedMUSD)
    {
        allocatedMUSD = destinationAllocations[_destination];
        uint256 _allocationCap = policyEngine.allocationCap(address(this), _destination);
        bool _approved = policyEngine.isDestinationApproved(address(this), _destination);
        uint256 _remainingCapacity;
        address _yieldToken;
        address _pairedToken;
        address _handler;
        address _receiptToken;
        uint256 _receiptBalance;
        uint256 _claimableYield;
        bool _supportsSavingsRate;
        bool _supportsTigrisStablePool;

        if (_allocationCap > allocatedMUSD) {
            _remainingCapacity = _allocationCap - allocatedMUSD;
        }

        if (_destination.code.length > 0) {
            try IMUSDSavingsRate(_destination).yieldToken() returns (address _reportedYieldToken) {
                _yieldToken = _reportedYieldToken;
                _receiptToken = _destination;
                _receiptBalance = IMUSDSavingsRate(_destination).balanceOf(address(this));
                _claimableYield = _previewSavingsRateClaimableYield(IMUSDSavingsRate(_destination), _receiptBalance);
                _supportsSavingsRate = true;
            } catch { }
        }

        if (allocationRouter.code.length > 0) {
            try IAllocationRouterView(allocationRouter).handlers(_destination) returns (address _registeredHandler) {
                _handler = _registeredHandler;
                if (_registeredHandler != address(0)) {
                    try ITigrisStablePoolHandlerMetadata(_registeredHandler).pairedToken() returns (
                        address _reportedPairedToken
                    ) {
                        _pairedToken = _reportedPairedToken;
                        _receiptToken = _destination;
                        _receiptBalance = IERC20(_destination).balanceOf(address(this));
                        _supportsTigrisStablePool = true;
                    } catch { }
                }
            } catch { }
        }

        exposure = DestinationExposure({
            destination: _destination,
            approved: _approved,
            allocationCap: _allocationCap,
            allocatedMUSD: allocatedMUSD,
            remainingCapacity: _remainingCapacity,
            yieldToken: _yieldToken,
            pairedToken: _pairedToken,
            handler: _handler,
            receiptToken: _receiptToken,
            receiptBalance: _receiptBalance,
            claimableYield: _claimableYield,
            supportsSavingsRate: _supportsSavingsRate,
            supportsTigrisStablePool: _supportsTigrisStablePool
        });
    }

    /// @notice Reverts when a savings destination reports a non-MUSD yield token.
    /// @param _savingsRate Savings destination being validated.
    function _requireSupportedYieldToken(IMUSDSavingsRate _savingsRate) internal view {
        address _yieldToken = _savingsRate.yieldToken();
        require(_yieldToken == address(musdToken), UnsupportedYieldToken(address(musdToken), _yieldToken));
    }

    /// @notice Reverts when the allocation router is not configured for workflow-scoped sleeve actions.
    function _requireAllocationRouterConfigured() internal view {
        require(allocationRouter != address(0), AllocationRouterNotConfigured());
    }

    /// @notice Bubbles custom errors and revert strings returned by destination protocols.
    /// @param _returnData Revert data from the failed external call.
    function _revertWithReturnData(bytes memory _returnData) internal pure {
        if (_returnData.length == 0) {
            revert();
        }

        assembly {
            revert(add(_returnData, 32), mload(_returnData))
        }
    }

    /// @notice Previews claimable savings-vault yield including any uncheckpointed yield index delta.
    /// @param _savingsRate Savings destination being queried.
    /// @param _receiptBalance Current savings receipt balance held by the treasury.
    /// @return claimableYield Current claimable treasury yield.
    function _previewSavingsRateClaimableYield(IMUSDSavingsRate _savingsRate, uint256 _receiptBalance)
        internal
        view
        returns (uint256 claimableYield)
    {
        claimableYield = _savingsRate.claimableYield(address(this));

        if (_receiptBalance == 0) {
            return claimableYield;
        }

        uint256 _yieldIndex = _savingsRate.yieldIndex();
        uint256 _accountYieldIndex = _savingsRate.supplyYieldIndex(address(this));

        if (_yieldIndex > _accountYieldIndex) {
            claimableYield += (_receiptBalance * (_yieldIndex - _accountYieldIndex)) / 1e18;
        }
    }

    /// @notice Reverts when the caller is neither the configured allocation router nor a registered handler.
    function _requireAuthorizedAllocationCaller() internal view {
        if (msg.sender == allocationRouter) {
            return;
        }

        if (allocationRouter != address(0)) {
            try IAllocationRouterAuthority(allocationRouter).isAuthorizedHandler(msg.sender) returns (
                bool _authorized
            ) {
                require(_authorized, UnauthorizedCaller(msg.sender));
                return;
            } catch { }
        }

        revert UnauthorizedCaller(msg.sender);
    }

    /// @notice Reverts when the caller is neither the configured BTC reserve router nor a registered BTC handler.
    function _requireAuthorizedBTCReserveCaller() internal view {
        if (msg.sender == btcReserveRouter) {
            return;
        }

        if (btcReserveRouter != address(0)) {
            try IBTCReserveRouterAuthority(btcReserveRouter).isAuthorizedBTCHandler(msg.sender) returns (
                bool _authorized
            ) {
                require(_authorized, UnauthorizedCaller(msg.sender));
                return;
            } catch { }
        }

        revert UnauthorizedCaller(msg.sender);
    }

    /// @notice Validates a protocol-native trove adjustment before forwarding to Mezo.
    /// @param _actor Treasury actor requesting the adjustment.
    /// @param _collateralDeposit BTC collateral being added in the transaction.
    /// @param _collateralWithdrawal BTC collateral being withdrawn from the trove.
    /// @param _debtChange MUSD debt change requested.
    /// @param _isDebtIncrease Whether the debt change increases or decreases debt.
    function _validatePositionAdjustment(
        address _actor,
        uint256 _collateralDeposit,
        uint256 _collateralWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) internal view {
        require(_collateralDeposit > 0 || _collateralWithdrawal > 0 || _debtChange > 0, InvalidPositionAdjustment());

        uint256 _currentCollateral = positionCollateral();
        uint256 _currentDebt = positionTotalDebt();

        if (_collateralDeposit > 0) {
            policyEngine.validateCollateralDeposit(address(this), _actor, _collateralDeposit);
        }

        if (_collateralWithdrawal > 0) {
            require(
                _currentCollateral >= _collateralWithdrawal,
                PositionCollateralExceeded(_collateralWithdrawal, _currentCollateral)
            );
            policyEngine.validateCollateralWithdrawal(address(this), _actor, _collateralWithdrawal);
        }

        if (_debtChange > 0) {
            if (_isDebtIncrease) {
                policyEngine.validateBorrow(address(this), _actor, _debtChange, idleMUSD);
            } else {
                uint256 _currentCloseDebt = positionCloseDebt();
                require(_currentCloseDebt >= _debtChange, PositionCloseDebtExceeded(_debtChange, _currentCloseDebt));
                policyEngine.validateDebtRepayment(address(this), _actor, _debtChange, idleMUSD);
            }
        }

        if (_collateralWithdrawal > 0 || (_debtChange > 0 && _isDebtIncrease)) {
            policyEngine.validateProjectedPosition(
                address(this),
                _actor,
                _currentCollateral + _collateralDeposit - _collateralWithdrawal,
                _projectedAdjustedDebt(_currentDebt, _debtChange, _isDebtIncrease),
                collateralPrice()
            );
        }
    }

    /// @notice Estimates protocol debt after an open action using current fee configuration.
    /// @param _debtAmount MUSD amount requested by the treasury.
    /// @return debt Projected full position debt, including known fee and gas-compensation components.
    function _projectedOpenDebt(uint256 _debtAmount) internal view returns (uint256 debt) {
        debt = _debtAmount + _borrowingFee(_debtAmount) + positionGasCompensation();
    }

    /// @notice Estimates protocol debt after a generic adjustment.
    /// @param _currentDebt Current full protocol debt.
    /// @param _debtChange Requested debt change.
    /// @param _isDebtIncrease Whether debt is increasing.
    /// @return debt Projected full protocol debt.
    function _projectedAdjustedDebt(uint256 _currentDebt, uint256 _debtChange, bool _isDebtIncrease)
        internal
        view
        returns (uint256 debt)
    {
        if (_debtChange == 0) {
            return _currentDebt;
        }

        if (_isDebtIncrease) {
            return _currentDebt + _debtChange + _borrowingFee(_debtChange);
        }

        return _currentDebt - _debtChange;
    }

    /// @notice Reads the Mezo borrowing fee for projected-risk checks.
    /// @param _debtAmount MUSD debt amount being added.
    /// @return fee Borrowing fee quoted by the connected borrower operations contract.
    function _borrowingFee(uint256 _debtAmount) internal view returns (uint256 fee) {
        if (address(borrowerOperations) == address(0) || _debtAmount == 0) {
            return 0;
        }

        return borrowerOperations.getBorrowingFee(_debtAmount);
    }

    /// @notice Returns whether risk data can be computed for the provided position and price inputs.
    /// @param _positionCollateral Position collateral used in the health calculation.
    /// @param _positionDebt Position debt used in the health calculation.
    /// @param _collateralPrice Current collateral price used in the health calculation.
    /// @return available Whether a price-backed risk computation is possible.
    function _riskDataAvailable(uint256 _positionCollateral, uint256 _positionDebt, uint256 _collateralPrice)
        internal
        pure
        returns (bool available)
    {
        return _positionCollateral > 0 && _positionDebt > 0 && _collateralPrice > 0;
    }

    /// @notice Returns the collateral market value for a position using a 1e18-scaled collateral price.
    /// @param _positionCollateral Position collateral amount.
    /// @param _collateralPrice Current collateral price scaled by 1e18.
    /// @return valueMUSD Collateral market value in MUSD terms, scaled by 1e18.
    function _collateralValueMUSD(uint256 _positionCollateral, uint256 _collateralPrice)
        internal
        pure
        returns (uint256 valueMUSD)
    {
        if (_positionCollateral == 0 || _collateralPrice == 0) {
            return 0;
        }

        return (_positionCollateral * _collateralPrice) / 1e18;
    }

    /// @notice Returns the collateral ratio for a position in basis points.
    /// @param _positionCollateral Position collateral amount.
    /// @param _positionDebt Position debt amount.
    /// @param _collateralPrice Current collateral price scaled by 1e18.
    /// @return ratioBps Collateral ratio in basis points.
    function _collateralRatioBps(uint256 _positionCollateral, uint256 _positionDebt, uint256 _collateralPrice)
        internal
        pure
        returns (uint256 ratioBps)
    {
        if (!_riskDataAvailable(_positionCollateral, _positionDebt, _collateralPrice)) {
            return 0;
        }

        uint256 _collateralValue = _collateralValueMUSD(_positionCollateral, _collateralPrice);
        return (_collateralValue * 10_000) / _positionDebt;
    }

    /// @notice Returns the collateral price at which the position would exactly equal a target ratio.
    /// @param _positionCollateral Position collateral amount.
    /// @param _positionDebt Position debt amount.
    /// @param _targetRatioBps Target collateral ratio in basis points.
    /// @return thresholdPrice Price scaled by 1e18 at which the position would meet the target ratio.
    function _thresholdPrice(uint256 _positionCollateral, uint256 _positionDebt, uint256 _targetRatioBps)
        internal
        pure
        returns (uint256 thresholdPrice)
    {
        if (_positionCollateral == 0 || _positionDebt == 0 || _targetRatioBps == 0) {
            return 0;
        }

        return (_positionDebt * _targetRatioBps * 1e18) / (_positionCollateral * 10_000);
    }

    /// @notice Returns the smaller of two unsigned integers.
    /// @param _a First candidate value.
    /// @param _b Second candidate value.
    /// @return minimum Smaller of the two inputs.
    function _min(uint256 _a, uint256 _b) internal pure returns (uint256 minimum) {
        return _a < _b ? _a : _b;
    }

    /// @notice Reverts when no active Mezo position exists for the treasury account.
    function _requireActivePosition() internal view {
        require(positionActive(), NoActivePosition());
    }
}
