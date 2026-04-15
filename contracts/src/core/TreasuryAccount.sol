// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBorrowerOperations } from "../interfaces/IBorrowerOperations.sol";
import { IGovernableVariables } from "../interfaces/IGovernableVariables.sol";
import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";
import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";
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

    error InvalidAllocationRouter(address allocationRouter);
    error InvalidBorrowerOperations(address borrowerOperations);
    error InvalidMUSDToken(address musdToken);
    error InvalidPolicyEngine(address policyEngine);
    error InvalidPositionAdjustment();
    error NoActivePosition();
    error NotPendingOwner(address caller);
    error PositionCloseDebtExceeded(uint256 amount, uint256 currentCloseDebt);
    error PositionCollateralExceeded(uint256 amount, uint256 currentCollateral);
    error PositionAlreadyOpen();
    error UnsupportedYieldToken(address expected, address actual);
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

    /// @notice Per-destination treasury exposure used in composition snapshots.
    /// @param destination Destination address being reported.
    /// @param approved Whether the destination is approved by treasury policy.
    /// @param allocationCap Maximum allowed deployment for the destination.
    /// @param allocatedMUSD Current MUSD allocated to the destination.
    /// @param remainingCapacity Additional MUSD that can be allocated before the cap is reached.
    /// @param yieldToken Yield token exposed by the destination when supported. Zero for unsupported destination types.
    /// @param receiptToken Receipt token address held by the Treasury Account for the destination when supported.
    ///        Zero for unsupported destination types.
    /// @param receiptBalance Current destination receipt-token balance held by the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param claimableYield Current claimable yield exposed by the destination for the Treasury Account.
    ///        Zero for unsupported destination types.
    /// @param supportsSavingsRate Whether the destination supports MUSDSavingsRate-compatible reporting.
    struct DestinationExposure {
        address destination;
        bool approved;
        uint256 allocationCap;
        uint256 allocatedMUSD;
        uint256 remainingCapacity;
        address yieldToken;
        address receiptToken;
        uint256 receiptBalance;
        uint256 claimableYield;
        bool supportsSavingsRate;
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

    /// @notice Deposits idle MUSD into the configured MUSD Savings Rate vault through the trusted adapter flow.
    /// @param _actor Treasury actor on whose behalf the deposit is being performed.
    /// @param _savingsRate Savings Rate destination receiving the principal.
    /// @param _amount Amount of MUSD principal being deposited.
    /// @return mintedShares Amount of sMUSD minted to the Treasury Account.
    function depositIntoSavingsRateFromAdapter(address _actor, address _savingsRate, uint256 _amount)
        external
        returns (uint256 mintedShares)
    {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));

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
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));

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
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));

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
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));

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
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));

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
            address _destination = _destinations[_i];
            uint256 _allocatedMUSD = destinationAllocations[_destination];
            uint256 _allocationCap = policyEngine.allocationCap(address(this), _destination);
            bool _approved = policyEngine.isDestinationApproved(address(this), _destination);
            uint256 _remainingCapacity;
            address _yieldToken;
            address _receiptToken;
            uint256 _receiptBalance;
            uint256 _claimableYield;
            bool _supportsSavingsRate;

            if (_allocationCap > _allocatedMUSD) {
                _remainingCapacity = _allocationCap - _allocatedMUSD;
            }

            if (_destination.code.length > 0) {
                try IMUSDSavingsRate(_destination).yieldToken() returns (address _reportedYieldToken) {
                    _yieldToken = _reportedYieldToken;
                    _receiptToken = _destination;
                    _receiptBalance = IMUSDSavingsRate(_destination).balanceOf(address(this));
                    _claimableYield = IMUSDSavingsRate(_destination).claimableYield(address(this));
                    _supportsSavingsRate = true;
                } catch { }
            }

            _totalAllocatedMUSD += _allocatedMUSD;
            _exposures[_i] = DestinationExposure({
                destination: _destination,
                approved: _approved,
                allocationCap: _allocationCap,
                allocatedMUSD: _allocatedMUSD,
                remainingCapacity: _remainingCapacity,
                yieldToken: _yieldToken,
                receiptToken: _receiptToken,
                receiptBalance: _receiptBalance,
                claimableYield: _claimableYield,
                supportsSavingsRate: _supportsSavingsRate
            });
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

    function _requireSupportedYieldToken(IMUSDSavingsRate _savingsRate) internal view {
        address _yieldToken = _savingsRate.yieldToken();
        require(_yieldToken == address(musdToken), UnsupportedYieldToken(address(musdToken), _yieldToken));
    }

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

    function _requireActivePosition() internal view {
        require(positionActive(), NoActivePosition());
    }
}
