// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { TreasuryAccount } from "./TreasuryAccount.sol";

/// @title TreasuryAutomationExecutor
/// @notice Bounded workflow runner for TreasuryOS automated treasury operations.
/// @dev This executor never custody assets and intentionally avoids arbitrary multicall. Each method maps to a
/// specific treasury workflow that is independently enforced by Treasury Account policy.
contract TreasuryAutomationExecutor is Ownable2Step, Pausable {
    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when an automation operator authorization changes.
    /// @param operator Automation operator whose access changed.
    /// @param authorized New authorization state.
    event AutomationOperatorAuthorizationUpdated(address indexed operator, bool authorized);
    /// @notice Emitted when a liquidity-buffer restoration workflow executes.
    /// @param treasuryAccount Treasury Account whose buffer was restored.
    /// @param operator Automation operator that initiated the workflow.
    /// @param destination Sleeve destination unwound for the restore.
    /// @param requestedMaxAmount Maximum amount the workflow was allowed to unwind.
    /// @param restoredAmount Actual idle MUSD restored to the treasury boundary.
    event BufferRestoreExecuted(
        address indexed treasuryAccount,
        address indexed operator,
        address indexed destination,
        uint256 requestedMaxAmount,
        uint256 restoredAmount
    );
    /// @notice Emitted when a de-risk repayment workflow executes.
    /// @param treasuryAccount Treasury Account whose position was de-risked.
    /// @param operator Automation operator that initiated the workflow.
    /// @param destination Sleeve destination unwound for the repayment.
    /// @param requestedWithdrawAmount Maximum sleeve amount the workflow was allowed to unwind.
    /// @param actualWithdrawAmount Actual idle MUSD restored to the treasury boundary.
    /// @param requestedRepayAmount Target debt-repayment amount for the workflow.
    /// @param actualRepaidAmount Actual MUSD repaid against the treasury position.
    event DeRiskRepaymentExecuted(
        address indexed treasuryAccount,
        address indexed operator,
        address indexed destination,
        uint256 requestedWithdrawAmount,
        uint256 actualWithdrawAmount,
        uint256 requestedRepayAmount,
        uint256 actualRepaidAmount
    );
    /// @notice Emitted when automation adds accounted idle BTC to active collateral.
    /// @param treasuryAccount Treasury Account whose position received collateral.
    /// @param operator Automation operator that initiated the workflow.
    /// @param amount Idle BTC amount added as collateral.
    event IdleBTCCollateralTopUpExecuted(address indexed treasuryAccount, address indexed operator, uint256 amount);

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when an automation operator address is zero.
    /// @param operator Invalid operator address.
    error InvalidAutomationOperator(address operator);
    /// @notice Raised when a Treasury Account address is zero.
    /// @param treasuryAccount Invalid Treasury Account address.
    error InvalidTreasuryAccount(address treasuryAccount);
    /// @notice Raised when a sleeve destination address is zero.
    /// @param destination Invalid destination address.
    error InvalidDestination(address destination);
    /// @notice Raised when a workflow amount is zero or otherwise invalid.
    /// @param amount Invalid amount value.
    error InvalidAmount(uint256 amount);
    /// @notice Raised when a caller is not allowed to trigger bounded automation workflows.
    /// @param caller Unauthorized caller.
    error UnauthorizedAutomationCaller(address caller);

    // =============================================================
    // Storage
    // =============================================================

    /// @notice Tracks which callers may trigger automation workflows through this executor.
    mapping(address operator => bool authorized) public automationOperators;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _owner Initial owner responsible for operator administration and pause control.
    constructor(address _owner) Ownable(_owner) { }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Authorizes or revokes an automation operator.
    /// @param _operator Automation caller whose access is being updated.
    /// @param _authorized New authorization state.
    function setAutomationOperator(address _operator, bool _authorized) external onlyOwner {
        require(_operator != address(0), InvalidAutomationOperator(_operator));

        automationOperators[_operator] = _authorized;

        emit AutomationOperatorAuthorizationUpdated(_operator, _authorized);
    }

    /// @notice Pauses bounded workflow execution.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses bounded workflow execution.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Restores a treasury liquidity buffer from a configured sleeve.
    /// @param _treasuryAccount Treasury Account being operated.
    /// @param _destination Destination being unwound for liquidity restoration.
    /// @param _maxAmount Maximum sleeve allocation amount that may be withdrawn.
    /// @return restoredAmount Actual MUSD restored to idle treasury balance.
    function restoreBufferFromSavings(TreasuryAccount _treasuryAccount, address _destination, uint256 _maxAmount)
        external
        whenNotPaused
        returns (uint256 restoredAmount)
    {
        _requireAuthorizedAutomationCaller();
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_maxAmount > 0, InvalidAmount(_maxAmount));

        restoredAmount = _treasuryAccount.restoreLiquidityBuffer(_destination, _maxAmount);

        emit BufferRestoreExecuted(address(_treasuryAccount), msg.sender, _destination, _maxAmount, restoredAmount);
    }

    /// @notice De-risks a treasury position by unwinding a sleeve and repaying debt in one bounded workflow.
    /// @param _treasuryAccount Treasury Account being operated.
    /// @param _destination Destination being unwound for repayment.
    /// @param _maxWithdrawAmount Maximum sleeve allocation amount that may be withdrawn.
    /// @param _targetRepayAmount Target debt-repayment amount.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    /// @return actualWithdrawAmount Actual MUSD restored to idle treasury balance.
    /// @return actualRepaidAmount Actual MUSD repaid against the treasury position.
    function deRiskByRepayingFromSleeve(
        TreasuryAccount _treasuryAccount,
        address _destination,
        uint256 _maxWithdrawAmount,
        uint256 _targetRepayAmount,
        address _upperHint,
        address _lowerHint
    ) external whenNotPaused returns (uint256 actualWithdrawAmount, uint256 actualRepaidAmount) {
        _requireAuthorizedAutomationCaller();
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_maxWithdrawAmount > 0, InvalidAmount(_maxWithdrawAmount));
        require(_targetRepayAmount > 0, InvalidAmount(_targetRepayAmount));

        (actualWithdrawAmount, actualRepaidAmount) = _treasuryAccount.withdrawFromDestinationAndRepay(
            _destination, _maxWithdrawAmount, _targetRepayAmount, _upperHint, _lowerHint
        );

        emit DeRiskRepaymentExecuted(
            address(_treasuryAccount),
            msg.sender,
            _destination,
            _maxWithdrawAmount,
            actualWithdrawAmount,
            _targetRepayAmount,
            actualRepaidAmount
        );
    }

    /// @notice Adds accounted idle BTC reserve to Mezo collateral through a bounded automation path.
    /// @param _treasuryAccount Treasury Account being operated.
    /// @param _amount Idle BTC amount to move into active collateral.
    /// @param _upperHint Upper insertion hint for Mezo sorted troves.
    /// @param _lowerHint Lower insertion hint for Mezo sorted troves.
    function topUpCollateralFromIdleBTC(
        TreasuryAccount _treasuryAccount,
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external whenNotPaused {
        _requireAuthorizedAutomationCaller();
        require(address(_treasuryAccount) != address(0), InvalidTreasuryAccount(address(_treasuryAccount)));
        require(_amount > 0, InvalidAmount(_amount));

        _treasuryAccount.addIdleBTCToCollateral(_amount, _upperHint, _lowerHint);

        emit IdleBTCCollateralTopUpExecuted(address(_treasuryAccount), msg.sender, _amount);
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Reverts unless the caller is the owner or an authorized automation operator.
    function _requireAuthorizedAutomationCaller() internal view {
        if (msg.sender == owner() || automationOperators[msg.sender]) {
            return;
        }

        revert UnauthorizedAutomationCaller(msg.sender);
    }
}
