// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ITreasuryPolicyEngine
/// @notice Defines the TreasuryOS internal policy checks used by Treasury Accounts.
interface ITreasuryPolicyEngine {
    /// @notice Sets the Treasury Account factory allowed to initialize accounts.
    /// @param _factory Factory address to authorize.
    function setFactory(address _factory) external;

    /// @notice Initial policy configuration for a Treasury Account.
    /// @param operator Address allowed to operate the treasury within configured limits.
    /// @param approver Address allowed to approve larger or more sensitive actions.
    /// @param liquidityBuffer Minimum idle MUSD that must remain undeployed.
    /// @param approvalThreshold Max amount the operator may move without approver authority.
    /// @param warningCollateralRatioBps Treasury-defined warning threshold for collateral health, in basis points.
    /// @param criticalCollateralRatioBps Treasury-defined critical threshold for collateral health, in basis points.
    /// @param automationEnabled Whether low-risk automation is enabled for the account.
    /// @param startPaused Whether the treasury should begin in a paused state.
    /// @param approvedDestinations Destinations that may receive treasury funds.
    /// @param destinationCaps Per-destination allocation caps aligned to `approvedDestinations`.
    struct AccountPolicyConfig {
        address operator;
        address approver;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
        uint256 warningCollateralRatioBps;
        uint256 criticalCollateralRatioBps;
        bool automationEnabled;
        bool startPaused;
        address[] approvedDestinations;
        uint256[] destinationCaps;
    }

    /// @notice Initializes policy state for a newly deployed Treasury Account.
    /// @param _account Treasury Account being initialized.
    /// @param _treasuryAdmin Treasury administrator for the account.
    /// @param _config Initial role and policy configuration.
    function initializeAccount(address _account, address _treasuryAdmin, AccountPolicyConfig calldata _config) external;

    /// @notice Updates the treasury administrator recorded for an account.
    /// @param _account Treasury Account whose administrator is changing.
    /// @param _treasuryAdmin New treasury administrator for the account.
    function updateTreasuryAdmin(address _account, address _treasuryAdmin) external;

    /// @notice Updates the dedicated automation executor for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _executor Automation executor allowed to perform bounded operational reactions.
    function updateAutomationExecutor(address _account, address _executor) external;

    /// @notice Updates treasury health thresholds for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _warningCollateralRatioBps Warning threshold for collateral health, in basis points.
    /// @param _criticalCollateralRatioBps Critical threshold for collateral health, in basis points.
    function updateAutomationThresholds(
        address _account,
        uint256 _warningCollateralRatioBps,
        uint256 _criticalCollateralRatioBps
    ) external;

    /// @notice Updates the maximum automated action sizes for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _maxAutoBufferRestore Maximum MUSD amount that automation may restore back to idle liquidity.
    /// @param _maxAutoDebtRepay Maximum MUSD amount that automation may repay against debt.
    function updateAutomationLimits(address _account, uint256 _maxAutoBufferRestore, uint256 _maxAutoDebtRepay) external;

    /// @notice Updates which automated workflow categories are permitted for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _allowAutoSavingsWithdraw Whether automation may unwind approved savings liquidity.
    /// @param _allowAutoDebtRepay Whether automation may repay debt using bounded workflows.
    function updateAutomationCapabilities(address _account, bool _allowAutoSavingsWithdraw, bool _allowAutoDebtRepay)
        external;

    /// @notice Enables or disables bounded automation for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _automationEnabled New automation-enabled state.
    function updateAutomationEnabled(address _account, bool _automationEnabled) external;

    /// @notice Validates a borrow or balance-increasing action for an account.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _amount Amount being added to the treasury.
    /// @param _idleBalance Current idle MUSD balance before the action.
    function validateBorrow(address _account, address _actor, uint256 _amount, uint256 _idleBalance) external view;

    /// @notice Validates a debt repayment action funded from idle treasury MUSD.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _amount Amount of MUSD being repaid.
    /// @param _idleBalance Current idle MUSD balance before repayment.
    function validateDebtRepayment(address _account, address _actor, uint256 _amount, uint256 _idleBalance)
        external
        view;

    /// @notice Validates adding BTC collateral to an existing Mezo position.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _amount Amount of BTC collateral being added.
    function validateCollateralDeposit(address _account, address _actor, uint256 _amount) external view;

    /// @notice Validates withdrawing BTC collateral from an existing Mezo position.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _amount Amount of BTC collateral being withdrawn.
    function validateCollateralWithdrawal(address _account, address _actor, uint256 _amount) external view;

    /// @notice Validates fully closing a Mezo position.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _idleBalance Current idle MUSD balance before close.
    /// @param _positionCloseDebt Current protocol debt that must be repaid to close the position.
    function validateClosePosition(address _account, address _actor, uint256 _idleBalance, uint256 _positionCloseDebt)
        external
        view;

    /// @notice Validates claiming yield from an approved treasury destination.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    function validateYieldClaim(address _account, address _actor) external view;

    /// @notice Validates that an actor may execute bounded automated treasury operations.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the automation action.
    function validateAutomationExecution(address _account, address _actor) external view;

    /// @notice Validates an automated liquidity-buffer restoration workflow.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the automation action.
    /// @param _destination Approved destination being unwound.
    /// @param _amount Amount requested for restoration.
    function validateBufferRestore(address _account, address _actor, address _destination, uint256 _amount)
        external
        view;

    /// @notice Validates an automated de-risk repayment workflow.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the automation action.
    /// @param _destination Approved destination being unwound.
    /// @param _amount Amount requested for debt reduction.
    function validateDeRiskRepayment(address _account, address _actor, address _destination, uint256 _amount)
        external
        view;

    /// @notice Validates a treasury disbursement from idle MUSD to an external recipient.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _recipient Recipient of the treasury cash movement.
    /// @param _amount Amount of MUSD being disbursed.
    /// @param _idleBalance Current idle MUSD balance before disbursement.
    function validateDisbursement(
        address _account,
        address _actor,
        address _recipient,
        uint256 _amount,
        uint256 _idleBalance
    ) external view;

    /// @notice Validates a withdrawal-accounting settlement reported by a destination handler.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller responsible for the routed action.
    /// @param _destination Destination being reduced.
    /// @param _allocationAmount Amount of tracked allocation being reduced.
    /// @param _currentAllocation Current deployed amount for the destination before settlement.
    function validateWithdrawalSettlement(
        address _account,
        address _actor,
        address _destination,
        uint256 _allocationAmount,
        uint256 _currentAllocation
    ) external view;

    /// @notice Validates deployment of idle MUSD into a destination.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _destination Destination receiving funds.
    /// @param _amount Amount being allocated.
    /// @param _idleBalance Current idle MUSD before allocation.
    /// @param _currentAllocation Current deployed amount for the destination.
    function validateAllocate(
        address _account,
        address _actor,
        address _destination,
        uint256 _amount,
        uint256 _idleBalance,
        uint256 _currentAllocation
    ) external view;

    /// @notice Validates a withdrawal from a destination back into idle treasury balance.
    /// @param _account Treasury Account being checked.
    /// @param _actor Caller attempting the action.
    /// @param _destination Destination being withdrawn from.
    /// @param _amount Amount being withdrawn.
    /// @param _currentAllocation Current deployed amount for the destination.
    function validateWithdraw(
        address _account,
        address _actor,
        address _destination,
        uint256 _amount,
        uint256 _currentAllocation
    ) external view;

    /// @notice Updates the paused state for a Treasury Account.
    /// @param _account Treasury Account being updated.
    /// @param _paused New paused state.
    function setPause(address _account, bool _paused) external;

    /// @notice Returns whether a destination is approved for an account.
    /// @param _account Treasury Account being queried.
    /// @param _destination Destination to check.
    function isDestinationApproved(address _account, address _destination) external view returns (bool);

    /// @notice Returns the allocation cap for a destination.
    /// @param _account Treasury Account being queried.
    /// @param _destination Destination to check.
    function allocationCap(address _account, address _destination) external view returns (uint256);

    /// @notice Returns the current policy configuration for an account.
    /// @param _account Treasury Account being queried.
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
        );

    /// @notice Returns the configured treasury health thresholds for an account.
    /// @param _account Treasury Account being queried.
    /// @return warningCollateralRatioBps Treasury-defined warning threshold in basis points.
    /// @return criticalCollateralRatioBps Treasury-defined critical threshold in basis points.
    function getAccountRiskPolicy(address _account)
        external
        view
        returns (uint256 warningCollateralRatioBps, uint256 criticalCollateralRatioBps);

    /// @notice Returns the configured automation policy for an account.
    /// @param _account Treasury Account being queried.
    /// @return automationExecutor Dedicated automation executor address.
    /// @return maxAutoBufferRestore Maximum automated buffer-restore size.
    /// @return maxAutoDebtRepay Maximum automated debt-repayment size.
    /// @return allowAutoSavingsWithdraw Whether automation may unwind approved savings liquidity.
    /// @return allowAutoDebtRepay Whether automation may repay debt using bounded workflows.
    function getAccountAutomationPolicy(address _account)
        external
        view
        returns (
            address automationExecutor,
            uint256 maxAutoBufferRestore,
            uint256 maxAutoDebtRepay,
            bool allowAutoSavingsWithdraw,
            bool allowAutoDebtRepay
        );
}
