// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAllocationRouterAuthority } from "../interfaces/IAllocationRouterAuthority.sol";
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

    /// @notice Emitted when the connected Mezo borrower operations contract is updated.
    event BorrowerOperationsUpdated(address indexed borrowerOperations);
    /// @notice Emitted when the trusted allocation router is updated.
    event AllocationRouterUpdated(address indexed allocationRouter);
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

    /// @notice Raised when the allocation router address is zero.
    /// @param allocationRouter Invalid allocation router address.
    error InvalidAllocationRouter(address allocationRouter);
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
    /// @notice Raised when an account-level caller lacks the required authority.
    /// @param caller Unauthorized caller.
    error UnauthorizedCaller(address caller);

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
    /// @param pairedToken Paired stable token exposed by a Tigris stable-pool handler when supported.
    ///        Zero for unsupported destination types.
    /// @param handler Registered allocation handler for the destination when one exists.
    /// @param receiptToken Receipt token address held by the Treasury Account for the destination when supported.
    ///        Zero for unsupported destination types.
    /// @param receiptBalance Current destination receipt-token balance held by the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param claimableYield Current claimable yield exposed by the destination for the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param supportsSavingsRate Whether the destination supports MUSDSavingsRate-compatible reporting.
    /// @param supportsTigrisStablePool Whether the destination is routed by a Tigris stable-pool handler.
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

    /// @notice TreasuryOS policy engine enforcing internal treasury controls for this account.
    ITreasuryPolicyEngine public immutable policyEngine;
    /// @notice MUSD token used for debt repayment and treasury destination allocations.
    IERC20 public immutable musdToken;
    /// @notice Connected Mezo borrower operations contract used for position lifecycle calls.
    IBorrowerOperations public borrowerOperations;
    /// @notice Trusted allocation router allowed to orchestrate governed destination flows.
    address public allocationRouter;

    /// @notice Idle treasury-managed MUSD held inside the account and available for operations.
    uint256 public idleMUSD;
    /// @notice Idle BTC held directly by the Treasury Account outside the active Mezo position.
    uint256 public idleBTC;
    /// @notice Deployed MUSD amount tracked per approved destination.
    mapping(address destination => uint256 amount) public destinationAllocations;

    /// @param _owner Treasury administrator and initial owner for the account.
    /// @param _policyEngine Policy engine enforcing TreasuryOS internal controls.
    /// @param _musdToken MUSD token used by this Treasury Account.
    constructor(address _owner, ITreasuryPolicyEngine _policyEngine, IERC20 _musdToken) Ownable(_owner) {
        require(address(_policyEngine) != address(0), InvalidPolicyEngine(address(_policyEngine)));
        require(address(_musdToken) != address(0), InvalidMUSDToken(address(_musdToken)));

        policyEngine = _policyEngine;
        musdToken = _musdToken;
    }

    /// @notice Accepts BTC returned from Mezo position withdrawals and closes.
    receive() external payable { }

    /// @notice Opens a Mezo position owned by this Treasury Account and borrows MUSD into idle treasury balance.
    /// @param _musdAmount Amount of MUSD to draw into the Treasury Account.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint) external payable {
        require(address(borrowerOperations) != address(0), InvalidBorrowerOperations(address(borrowerOperations)));
        require(!positionActive(), PositionAlreadyOpen());

        policyEngine.validateBorrow(address(this), msg.sender, _musdAmount, idleMUSD);
        policyEngine.validateCollateralDeposit(address(this), msg.sender, msg.value);

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

    /// @notice Withdraws BTC collateral from the active Mezo position.
    /// @param _amount Amount of BTC collateral to withdraw.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function withdrawCollateral(uint256 _amount, address _upperHint, address _lowerHint) external {
        _requireActivePosition();

        uint256 _currentCollateral = positionCollateral();
        require(_currentCollateral >= _amount, PositionCollateralExceeded(_amount, _currentCollateral));

        policyEngine.validateCollateralWithdrawal(address(this), msg.sender, _amount);

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

    /// @notice Funds idle treasury MUSD so the account can restore working capital or repay debt.
    /// @param _amount Amount of MUSD transferred into the Treasury Account.
    function fundIdleMUSD(uint256 _amount) external {
        require(_amount > 0, InvalidAmount(_amount));

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        idleMUSD += _amount;

        emit IdleMUSDFunded(msg.sender, _amount, idleMUSD);
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
        require(_success, string(_result));
        return _result;
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

    /// @notice Finalizes a pending ownership transfer and syncs the policy engine's treasury admin.
    function acceptOwnership() public override {
        require(msg.sender == pendingOwner(), NotPendingOwner(msg.sender));

        address _previousTreasuryAdmin = owner();

        super.acceptOwnership();
        policyEngine.updateTreasuryAdmin(address(this), owner());

        emit TreasuryAdminSynced(_previousTreasuryAdmin, owner());
    }

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

        if (_collateralDeposit > 0) {
            policyEngine.validateCollateralDeposit(address(this), _actor, _collateralDeposit);
        }

        if (_collateralWithdrawal > 0) {
            uint256 _currentCollateral = positionCollateral();
            require(
                _currentCollateral >= _collateralWithdrawal,
                PositionCollateralExceeded(_collateralWithdrawal, _currentCollateral)
            );
            policyEngine.validateCollateralWithdrawal(address(this), _actor, _collateralWithdrawal);
        }

        if (_debtChange == 0) {
            return;
        }

        if (_isDebtIncrease) {
            policyEngine.validateBorrow(address(this), _actor, _debtChange, idleMUSD);
            return;
        }

        uint256 _currentCloseDebt = positionCloseDebt();
        require(_currentCloseDebt >= _debtChange, PositionCloseDebtExceeded(_debtChange, _currentCloseDebt));
        policyEngine.validateDebtRepayment(address(this), _actor, _debtChange, idleMUSD);
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

    /// @notice Reverts when no active Mezo position exists for the treasury account.
    function _requireActivePosition() internal view {
        require(positionActive(), NoActivePosition());
    }
}
