// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IGovernableVariables } from "./IGovernableVariables.sol";

/// @title IBorrowerOperations
/// @notice Production-oriented interface aligned to Mezo BorrowerOperations.
interface IBorrowerOperations {
    event ActivePoolAddressChanged(address _activePoolAddress);
    event BorrowingRateChanged(uint256 borrowingRate);
    event BorrowingRateProposed(uint256 proposedBorrowingRate, uint256 proposedBorrowingRateTime);
    event BorrowerOperationsSignaturesAddressChanged(address _borrowerOperationsSignaturesAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event GovernableVariablesAddressChanged(address _governableVariablesAddress);
    event InterestRateManagerAddressChanged(address _interestRateManagerAddress);
    event MUSDTokenAddressChanged(address _musdTokenAddress);
    event MinNetDebtChanged(uint256 _minNetDebt);
    event MinNetDebtProposed(uint256 _minNetDebt, uint256 _proposalTime);
    event PCVAddressChanged(address _pcvAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event RedemptionRateChanged(uint256 redemptionRate);
    event RedemptionRateProposed(uint256 proposedRedemptionRate, uint256 proposedRedemptionRateTime);
    event RefinancingFeePercentageChanged(uint8 _refinanceFeePercentage);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event TroveCreated(address indexed _borrower, uint256 arrayIndex);
    event TroveUpdated(
        address indexed _borrower,
        uint256 _principal,
        uint256 _interest,
        uint256 _coll,
        uint256 _stake,
        uint16 _interestRate,
        uint256 _lastInterestUpdateTime,
        uint8 _operation
    );
    event BorrowingFeePaid(address indexed _borrower, uint256 _fee);
    event RefinancingFeePaid(address indexed _borrower, uint256 _fee);

    /// @notice Sets the dependent protocol contract addresses on BorrowerOperations.
    /// @param _addresses Ordered dependency array expected by the Mezo implementation.
    function setAddresses(address[13] memory _addresses) external;

    /// @notice Updates the refinancing fee percentage.
    /// @param _refinanceFeePercentage New refinancing fee percentage.
    function setRefinancingFeePercentage(uint8 _refinanceFeePercentage) external;

    /// @notice Opens a new trove for `msg.sender` with native BTC collateral and borrowed MUSD debt.
    /// @param _debtAmount MUSD debt amount to draw.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function openTrove(uint256 _debtAmount, address _upperHint, address _lowerHint) external payable;

    /// @notice Opens a trove on behalf of a borrower and directs minted MUSD to a recipient.
    /// @param _borrower Borrower owning the trove.
    /// @param _recipient Recipient of the minted MUSD.
    /// @param _debtAmount MUSD debt amount to draw.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function restrictedOpenTrove(
        address _borrower,
        address _recipient,
        uint256 _debtAmount,
        address _upperHint,
        address _lowerHint
    ) external payable;

    /// @notice Proposes a new minimum net debt value.
    /// @param _minNetDebt Proposed minimum net debt.
    function proposeMinNetDebt(uint256 _minNetDebt) external;

    /// @notice Approves the pending minimum net debt proposal.
    function approveMinNetDebt() external;

    /// @notice Proposes a new borrowing rate.
    /// @param _fee Proposed borrowing fee or rate value.
    function proposeBorrowingRate(uint256 _fee) external;

    /// @notice Approves the pending borrowing rate proposal.
    function approveBorrowingRate() external;

    /// @notice Proposes a new redemption rate.
    /// @param _fee Proposed redemption fee or rate value.
    function proposeRedemptionRate(uint256 _fee) external;

    /// @notice Approves the pending redemption rate proposal.
    function approveRedemptionRate() external;

    /// @notice Adds native BTC collateral to the caller's trove.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function addColl(address _upperHint, address _lowerHint) external payable;

    /// @notice Moves accumulated collateral gain into an existing trove.
    /// @param _borrower Borrower whose trove receives the collateral gain.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function moveCollateralGainToTrove(address _borrower, address _upperHint, address _lowerHint) external payable;

    /// @notice Withdraws BTC collateral from the caller's trove.
    /// @param _amount Amount of collateral to withdraw.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function withdrawColl(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Draws additional MUSD debt from the caller's trove.
    /// @param _amount Amount of MUSD to draw.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Repays MUSD debt against the caller's trove.
    /// @param _amount Amount of MUSD debt to repay.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;

    /// @notice Closes the caller's trove and releases collateral.
    function closeTrove() external;

    /// @notice Closes a trove on behalf of a borrower.
    /// @param _borrower Borrower whose trove is being closed.
    /// @param _caller Caller credited by the Mezo implementation.
    /// @param _recipient Recipient of released collateral.
    function restrictedCloseTrove(address _borrower, address _caller, address _recipient) external;

    /// @notice Refinances the caller's trove using current protocol settings.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function refinance(address _upperHint, address _lowerHint) external;

    /// @notice Refinances a borrower's trove on their behalf.
    /// @param _borrower Borrower whose trove is being refinanced.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function restrictedRefinance(address _borrower, address _upperHint, address _lowerHint) external;

    /// @notice Adjusts collateral and debt for the caller's trove in one operation.
    /// @param _collWithdrawal Amount of collateral to withdraw.
    /// @param _debtChange Amount of debt to change.
    /// @param _isDebtIncrease Whether `_debtChange` increases debt.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;

    /// @notice Adjusts a borrower's trove on their behalf.
    /// @param _borrower Borrower whose trove is being adjusted.
    /// @param _recipient Recipient of any MUSD or collateral released.
    /// @param _caller Caller credited by the implementation.
    /// @param _collWithdrawal Amount of collateral to withdraw.
    /// @param _mUSDChange Amount of debt to change.
    /// @param _isDebtIncrease Whether `_mUSDChange` increases debt.
    /// @param _upperHint Upper sorted-trove insertion hint.
    /// @param _lowerHint Lower sorted-trove insertion hint.
    function restrictedAdjustTrove(
        address _borrower,
        address _recipient,
        address _caller,
        uint256 _collWithdrawal,
        uint256 _mUSDChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;

    /// @notice Claims surplus collateral owed to the caller.
    function claimCollateral() external;

    /// @notice Claims surplus collateral on behalf of a borrower.
    /// @param _borrower Borrower whose collateral is being claimed.
    /// @param _recipient Recipient of the collateral.
    function restrictedClaimCollateral(address _borrower, address _recipient) external;

    /// @notice Returns the governable variables contract used by BorrowerOperations.
    function governableVariables() external view returns (IGovernableVariables);

    /// @notice Returns the active TroveManager used by BorrowerOperations.
    function troveManager() external view returns (address);

    /// @notice Returns the active price feed used by BorrowerOperations.
    function priceFeed() external view returns (address);

    /// @notice Returns the borrowing fee for a proposed debt amount.
    /// @param _debt Proposed debt amount.
    /// @return Borrowing fee charged by the protocol.
    function getBorrowingFee(uint256 _debt) external view returns (uint256);

    /// @notice Returns the redemption rate for a collateral draw amount.
    /// @param _collateralDrawn Amount of collateral drawn for redemption.
    /// @return Redemption rate charged by the protocol.
    function getRedemptionRate(uint256 _collateralDrawn) external view returns (uint256);

    /// @notice Returns the current minimum net debt parameter.
    function minNetDebt() external view returns (uint256);
}
