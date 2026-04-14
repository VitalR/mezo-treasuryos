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
    /// @param automationEnabled Whether low-risk automation is enabled for the account.
    /// @param startPaused Whether the treasury should begin in a paused state.
    /// @param approvedDestinations Destinations that may receive treasury funds.
    /// @param destinationCaps Per-destination allocation caps aligned to `approvedDestinations`.
    struct AccountPolicyConfig {
        address operator;
        address approver;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
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
    /// @param _positionDebtPrincipal Current tracked debt principal of the position.
    function validateClosePosition(
        address _account,
        address _actor,
        uint256 _idleBalance,
        uint256 _positionDebtPrincipal
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
}
