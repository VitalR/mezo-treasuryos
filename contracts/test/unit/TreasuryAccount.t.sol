// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../../src/adapters/MUSDSavingsRateHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDSavingsRate } from "../helpers/MockMUSDSavingsRate.sol";

contract TreasuryAccountTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _SAVINGS_VAULT = address(0xD00D);
    address internal constant _SECOND_DESTINATION = address(0xE11E);
    address internal constant _ALLOCATION_ADAPTER = address(0xF00D);
    address internal constant _OPERATING_RECIPIENT = address(0xABCD);
    address internal constant _AUTOMATION_EXECUTOR = address(0xA700);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDSavingsRate internal _mockSavingsVault;
    AllocationRouter internal _allocationRouter;
    MUSDSavingsRateHandler internal _savingsHandler;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(IERC20(_borrowerOperations.musdToken()), _policyEngine);
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _mockSavingsVault = new MockMUSDSavingsRate(_borrowerOperations.musdTokenContract());
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _savingsHandler = new MUSDSavingsRateHandler(_mockSavingsVault, address(_allocationRouter));

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);
        vm.deal(_AUTOMATION_EXECUTOR, 50 ether);
    }

    function test_DeployTreasuryAccount_InitializesPolicyState() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        (
            address _treasuryAdmin,
            address _operator,
            address _approver,
            uint256 _liquidityBuffer,
            uint256 _approvalThreshold,
            bool _automationEnabled,
            bool _paused,
            bool _initialized
        ) = _policyEngine.getAccountPolicy(address(_account));
        (uint256 _warningCollateralRatioBps, uint256 _criticalCollateralRatioBps) =
            _policyEngine.getAccountRiskPolicy(address(_account));

        assertEq(_account.owner(), _TREASURY_ADMIN);
        assertEq(address(_account.policyEngine()), address(_policyEngine));
        assertEq(_treasuryAdmin, _TREASURY_ADMIN);
        assertEq(_operator, _OPERATOR);
        assertEq(_approver, _APPROVER);
        assertEq(_liquidityBuffer, 200 ether);
        assertEq(_approvalThreshold, 100 ether);
        assertEq(_warningCollateralRatioBps, 18_000);
        assertEq(_criticalCollateralRatioBps, 15_000);
        assertTrue(_automationEnabled);
        assertFalse(_paused);
        assertTrue(_initialized);
        assertTrue(_policyEngine.isDestinationApproved(address(_account), _SAVINGS_VAULT));
        assertEq(_policyEngine.allocationCap(address(_account), _SAVINGS_VAULT), 500 ether);
    }

    function test_GetTreasuryHealthState_ReturnsHealthyStateForConfiguredPrice() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        TreasuryAccount.TreasuryHealthState memory _state = _account.getTreasuryHealthState();

        assertTrue(_state.positionActive);
        assertEq(_state.priceFeed, address(_borrowerOperations.priceFeedContract()));
        assertEq(_state.collateralPrice, 100 ether);
        assertEq(_state.collateralValueMUSD, 200 ether);
        assertEq(_state.positionCollateral, 2 ether);
        assertEq(_state.positionTotalDebt, 80 ether);
        assertEq(_state.positionCloseDebt, 80 ether);
        assertEq(_state.positionGasCompensation, 0);
        assertEq(_state.collateralRatioBps, 25_000);
        assertEq(_state.warningCollateralRatioBps, 18_000);
        assertEq(_state.criticalCollateralRatioBps, 15_000);
        assertEq(_state.warningThresholdPrice, 72 ether);
        assertEq(_state.criticalThresholdPrice, 60 ether);
        assertFalse(_state.belowWarningRatio);
        assertFalse(_state.belowCriticalRatio);
        assertTrue(_state.riskDataAvailable);
        assertTrue(_state.automationEnabled);
        assertFalse(_state.paused);
    }

    function test_GetTreasuryHealthState_ReturnsWarningStateWhenPriceDropsBelowWarningThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        _borrowerOperations.setCollateralPrice(70 ether);

        TreasuryAccount.TreasuryHealthState memory _state = _account.getTreasuryHealthState();

        assertEq(_state.collateralRatioBps, 17_500);
        assertTrue(_state.belowWarningRatio);
        assertFalse(_state.belowCriticalRatio);
    }

    function test_GetTreasuryHealthState_ReturnsCriticalStateWhenPriceDropsBelowCriticalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        _borrowerOperations.setCollateralPrice(55 ether);

        TreasuryAccount.TreasuryHealthState memory _state = _account.getTreasuryHealthState();

        assertEq(_state.collateralRatioBps, 13_750);
        assertTrue(_state.belowWarningRatio);
        assertTrue(_state.belowCriticalRatio);
    }

    function test_GetTreasuryHealthState_ReturnsUnavailableRiskStateWithoutPriceFeed() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        _borrowerOperations.setCollateralPrice(0);

        TreasuryAccount.TreasuryHealthState memory _state = _account.getTreasuryHealthState();

        assertEq(_state.collateralPrice, 0);
        assertEq(_state.collateralValueMUSD, 0);
        assertEq(_state.collateralRatioBps, 0);
        assertFalse(_state.belowWarningRatio);
        assertFalse(_state.belowCriticalRatio);
        assertFalse(_state.riskDataAvailable);
    }

    function test_GetTreasuryHealthState_ReturnsPausedFlagFromPolicy() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.setPause(true);

        TreasuryAccount.TreasuryHealthState memory _state = _account.getTreasuryHealthState();

        assertTrue(_state.paused);
        assertTrue(_state.automationEnabled);
    }

    function test_SetBorrowerOperations_TreasuryAdminCanSetBorrowerOperations() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowerOperations(address(_borrowerOperations));

        assertEq(address(_account.borrowerOperations()), address(_borrowerOperations));
    }

    function test_AcceptOwnership_PendingOwnerSyncsPolicyTreasuryAdmin() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();
        address _nextTreasuryAdmin = address(0xDD01);

        vm.prank(_TREASURY_ADMIN);
        _account.transferOwnership(_nextTreasuryAdmin);

        vm.prank(_nextTreasuryAdmin);
        _account.acceptOwnership();

        (address _treasuryAdmin,,,,,,,) = _policyEngine.getAccountPolicy(address(_account));

        assertEq(_account.owner(), _nextTreasuryAdmin);
        assertEq(_treasuryAdmin, _nextTreasuryAdmin);
    }

    function test_OpenTrove_OperatorCanOpenWithinApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        assertTrue(_account.positionActive());
        assertEq(_account.idleMUSD(), 80 ether);
        assertEq(_account.positionCollateral(), 2 ether);
        assertEq(_account.positionTotalDebt(), 80 ether);
        assertEq(_borrowerOperations.totalCollateral(address(_account)), 2 ether);
        assertEq(_borrowerOperations.totalDebt(address(_account)), 80 ether);
    }

    function test_OpenTrove_OperatorCannotOpenAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_WithdrawMUSD_ApproverCanIncreaseDebtAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.withdrawMUSD(120 ether, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 270 ether);
        assertEq(_account.positionTotalDebt(), 270 ether);
    }

    function test_RepayMUSD_OperatorCanRepayWithinApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _account.repayMUSD(50 ether, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 100 ether);
        assertEq(_account.positionTotalDebt(), 100 ether);
    }

    function test_FundIdleMUSD_IncreasesIdleTreasuryBalance() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        _borrowerOperations.musdTokenContract().mint(_TREASURY_ADMIN, 75 ether);

        vm.startPrank(_TREASURY_ADMIN);
        _borrowerOperations.musdTokenContract().approve(address(_account), 75 ether);
        _account.fundIdleMUSD(75 ether);
        vm.stopPrank();

        assertEq(_account.idleMUSD(), 75 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(address(_account)), 75 ether);
    }

    function test_DisburseMUSD_TreasuryAdminCanSendOperatingCash() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(300 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectEmit(true, true, false, true);
        emit TreasuryAccount.TreasuryDisbursed(_TREASURY_ADMIN, _OPERATING_RECIPIENT, 80 ether, 220 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 80 ether);

        assertEq(_account.idleMUSD(), 220 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(_OPERATING_RECIPIENT), 80 ether);
    }

    function test_DisburseMUSD_OperatorCannotSendAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(300 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 150 ether);
    }

    function test_AddCollateral_OperatorCanAddCollateralWhilePaused() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.setPause(true);

        vm.prank(_OPERATOR);
        _account.addCollateral{ value: 1 ether }(_UPPER_HINT, _LOWER_HINT);

        assertEq(_account.positionCollateral(), 3 ether);
    }

    function test_WithdrawCollateral_OperatorCannotWithdrawCollateral() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.UnauthorizedActor.selector, address(_account), _OPERATOR)
        );

        vm.prank(_OPERATOR);
        _account.withdrawCollateral(1 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_AdjustTrove_ApproverCanAdjustCollateralAndDebt() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 1 ether);

        vm.prank(_APPROVER);
        _account.adjustTrove{ value: 1 ether }(1 ether, 40 ether, false, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 110 ether);
        assertEq(_account.idleBTC(), 1 ether);
        assertEq(_account.positionCollateral(), 3 ether);
        assertEq(_account.positionTotalDebt(), 110 ether);
    }

    function test_CloseTrove_ApproverCanCloseAndRestoreBTC() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 2 ether);

        vm.prank(_APPROVER);
        _account.closeTrove();

        assertFalse(_account.positionActive());
        assertEq(_account.idleMUSD(), 0);
        assertEq(_account.idleBTC(), 2 ether);
        assertEq(_account.positionCollateral(), 0);
        assertEq(_account.positionTotalDebt(), 0);
    }

    function test_PositionDebtViews_ProtocolDebtIncludesFeeAndGasCompensation() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        _borrowerOperations.setBorrowingFee(1 ether);
        _borrowerOperations.setGasCompensation(20 ether);

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 80 ether);
        assertEq(_account.positionTotalDebt(), 101 ether);
        assertEq(_account.positionGasCompensation(), 20 ether);
        assertEq(_account.positionCloseDebt(), 81 ether);
    }

    function test_GetTreasuryPositionState_ReturnsProtocolBackedSnapshot() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        _borrowerOperations.setBorrowingFee(1 ether);
        _borrowerOperations.setGasCompensation(20 ether);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(250 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 50 ether);

        vm.prank(_APPROVER);
        _account.withdrawCollateral(1 ether, _UPPER_HINT, _LOWER_HINT);

        TreasuryAccount.TreasuryPositionState memory _state = _account.getTreasuryPositionState();

        assertEq(_state.owner, _TREASURY_ADMIN);
        assertEq(_state.borrowerOperations, address(_borrowerOperations));
        assertEq(_state.governableVariables, address(_borrowerOperations.governableVariables()));
        assertEq(_state.troveManager, address(_account.troveManager()));
        assertEq(_state.allocationRouter, address(0));
        assertEq(_state.idleMUSD, 200 ether);
        assertEq(_state.idleBTC, 1 ether);
        assertEq(_state.positionCollateral, 2 ether);
        assertEq(_state.positionTotalDebt, 271 ether);
        assertEq(_state.positionCloseDebt, 251 ether);
        assertEq(_state.positionGasCompensation, 20 ether);
        assertTrue(_state.positionActive);
    }

    function test_GetTreasuryComposition_ReturnsExposureBufferAndSavingsState() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount(address(_mockSavingsVault));

        vm.prank(_TREASURY_ADMIN);
        _account.setAllocationRouter(_ALLOCATION_ADAPTER);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_ALLOCATION_ADAPTER);
        _account.depositIntoSavingsRateFromAdapter(_OPERATOR, address(_mockSavingsVault), 100 ether);

        _mockSavingsVault.addClaimableYield(address(_account), 25 ether);

        address[] memory _destinations = new address[](2);
        _destinations[0] = address(_mockSavingsVault);
        _destinations[1] = _SECOND_DESTINATION;

        TreasuryAccount.TreasuryCompositionState memory _state = _account.getTreasuryComposition(_destinations);

        assertEq(_state.idleMUSD, 500 ether);
        assertEq(_state.idleBTC, 0);
        assertEq(_state.totalAllocatedMUSD, 100 ether);
        assertEq(_state.totalManagedMUSD, 600 ether);
        assertEq(_state.liquidityBuffer, 200 ether);
        assertEq(_state.deployableSurplus, 300 ether);
        assertEq(_state.approvalThreshold, 100 ether);
        assertTrue(_state.automationEnabled);
        assertFalse(_state.paused);

        assertEq(_state.exposures.length, 2);

        assertEq(_state.exposures[0].destination, address(_mockSavingsVault));
        assertTrue(_state.exposures[0].approved);
        assertEq(_state.exposures[0].allocationCap, 500 ether);
        assertEq(_state.exposures[0].allocatedMUSD, 100 ether);
        assertEq(_state.exposures[0].remainingCapacity, 400 ether);
        assertEq(_state.exposures[0].yieldToken, _borrowerOperations.musdToken());
        assertEq(_state.exposures[0].receiptToken, address(_mockSavingsVault));
        assertEq(_state.exposures[0].receiptBalance, 100 ether);
        assertEq(_state.exposures[0].claimableYield, 25 ether);
        assertTrue(_state.exposures[0].supportsSavingsRate);

        assertEq(_state.exposures[1].destination, _SECOND_DESTINATION);
        assertFalse(_state.exposures[1].approved);
        assertEq(_state.exposures[1].allocationCap, 0);
        assertEq(_state.exposures[1].allocatedMUSD, 0);
        assertEq(_state.exposures[1].remainingCapacity, 0);
        assertEq(_state.exposures[1].yieldToken, address(0));
        assertEq(_state.exposures[1].receiptToken, address(0));
        assertEq(_state.exposures[1].receiptBalance, 0);
        assertEq(_state.exposures[1].claimableYield, 0);
        assertFalse(_state.exposures[1].supportsSavingsRate);
    }

    function test_Allocate_OperatorCanAllocateWithinThresholdAndBuffer() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectEmit(true, false, false, true);
        emit TreasuryAccount.AllocationExecuted(_SAVINGS_VAULT, 100 ether, 500 ether, 100 ether);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        assertEq(_account.idleMUSD(), 500 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 100 ether);
    }

    function test_Allocate_UnapprovedDestinationReverts() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 5 ether }(500 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.NotApprovedDestination.selector, _SECOND_DESTINATION)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SECOND_DESTINATION, 50 ether);
    }

    function test_Allocate_LiquidityBufferBreachReverts() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(260 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.LiquidityBufferBreached.selector, 160 ether, 200 ether)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);
    }

    function test_SetPause_ApproverCanPauseAndBlockFurtherAllocation() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 4 ether }(400 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.setPause(true);

        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.PolicyPaused.selector, address(_account)));

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 50 ether);
    }

    function test_SetBorrowerOperations_NonOwnerReverts() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _account.setBorrowerOperations(address(_borrowerOperations));
    }

    function test_WithdrawFromDestination_RestoresIdleBalance() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        vm.prank(_OPERATOR);
        _account.withdrawFromDestination(_SAVINGS_VAULT, 40 ether);

        assertEq(_account.idleMUSD(), 540 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 60 ether);
    }

    function test_RestoreLiquidityBuffer_TreasuryAdminRestoresShortfallFromSavings() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 350 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 100 ether);

        vm.prank(_TREASURY_ADMIN);
        uint256 _restoredAmount = _account.restoreLiquidityBuffer(address(_mockSavingsVault), 80 ether);

        assertEq(_restoredAmount, 50 ether);
        assertEq(_account.idleMUSD(), 200 ether);
        assertEq(_account.destinationAllocations(address(_mockSavingsVault)), 300 ether);
    }

    function test_RestoreLiquidityBuffer_AutomationExecutorRestoresWithinConfiguredLimit() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();
        _configureAutomationForAccount(_account, 75 ether, 60 ether, true, true);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 350 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 120 ether);

        vm.prank(_AUTOMATION_EXECUTOR);
        uint256 _restoredAmount = _account.restoreLiquidityBuffer(address(_mockSavingsVault), 60 ether);

        assertEq(_restoredAmount, 60 ether);
        assertEq(_account.idleMUSD(), 190 ether);
        assertEq(_account.destinationAllocations(address(_mockSavingsVault)), 290 ether);
    }

    function test_RestoreLiquidityBuffer_AutomationLimitExceededReverts() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();
        _configureAutomationForAccount(_account, 40 ether, 60 ether, true, true);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 350 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryPolicyEngine.AutomationLimitExceeded.selector, bytes32("BUFFER_RESTORE"), 50 ether, 40 ether
            )
        );

        vm.prank(_AUTOMATION_EXECUTOR);
        _account.restoreLiquidityBuffer(address(_mockSavingsVault), 80 ether);
    }

    function test_WithdrawFromDestinationAndRepay_TreasuryAdminUnwindsSavingsAndRepaysDebt() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 250 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 230 ether);

        vm.prank(_TREASURY_ADMIN);
        (uint256 _actualWithdrawAmount, uint256 _actualRepaidAmount) = _account.withdrawFromDestinationAndRepay(
            address(_mockSavingsVault), 120 ether, 100 ether, _UPPER_HINT, _LOWER_HINT
        );

        assertEq(_actualWithdrawAmount, 120 ether);
        assertEq(_actualRepaidAmount, 100 ether);
        assertEq(_account.idleMUSD(), 140 ether);
        assertEq(_account.destinationAllocations(address(_mockSavingsVault)), 130 ether);
        assertEq(_account.positionTotalDebt(), 500 ether);
    }

    function test_WithdrawFromDestinationAndRepay_AutomationExecutorRepaysWithinConfiguredLimit() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();
        _configureAutomationForAccount(_account, 75 ether, 90 ether, true, true);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 220 ether);

        vm.prank(_TREASURY_ADMIN);
        _account.disburseMUSD(_OPERATING_RECIPIENT, 250 ether);

        vm.prank(_AUTOMATION_EXECUTOR);
        (uint256 _actualWithdrawAmount, uint256 _actualRepaidAmount) = _account.withdrawFromDestinationAndRepay(
            address(_mockSavingsVault), 120 ether, 90 ether, _UPPER_HINT, _LOWER_HINT
        );

        assertEq(_actualWithdrawAmount, 120 ether);
        assertEq(_actualRepaidAmount, 90 ether);
        assertEq(_account.idleMUSD(), 160 ether);
        assertEq(_account.destinationAllocations(address(_mockSavingsVault)), 100 ether);
        assertEq(_account.positionTotalDebt(), 510 ether);
    }

    function test_WithdrawFromDestinationAndRepay_AutomationLimitExceededReverts() public {
        TreasuryAccount _account = _deployConfiguredSavingsRouterTreasuryAccount();
        _configureAutomationForAccount(_account, 75 ether, 80 ether, true, true);

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_account), address(_mockSavingsVault), 220 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryPolicyEngine.AutomationLimitExceeded.selector, bytes32("DEBT_REPAY"), 90 ether, 80 ether
            )
        );

        vm.prank(_AUTOMATION_EXECUTOR);
        _account.withdrawFromDestinationAndRepay(
            address(_mockSavingsVault), 120 ether, 90 ether, _UPPER_HINT, _LOWER_HINT
        );
    }

    function _deployConfiguredTreasuryAccount() internal returns (TreasuryAccount _account) {
        _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowerOperations(address(_borrowerOperations));
    }

    function _deployConfiguredTreasuryAccount(address _approvedDestination)
        internal
        returns (TreasuryAccount _account)
    {
        _account = _deployTreasuryAccount(_defaultConfig(_approvedDestination));

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowerOperations(address(_borrowerOperations));
    }

    function _deployConfiguredSavingsRouterTreasuryAccount() internal returns (TreasuryAccount _account) {
        _account = _deployConfiguredTreasuryAccount(address(_mockSavingsVault));

        vm.prank(_TREASURY_ADMIN);
        _account.setAllocationRouter(address(_allocationRouter));

        vm.prank(_TREASURY_ADMIN);
        _allocationRouter.setHandler(address(_mockSavingsVault), _savingsHandler);
    }

    function _deployTreasuryAccount(ITreasuryPolicyEngine.AccountPolicyConfig memory _config)
        internal
        returns (TreasuryAccount)
    {
        return TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _config)));
    }

    function _configureAutomationForAccount(
        TreasuryAccount _account,
        uint256 _maxAutoBufferRestore,
        uint256 _maxAutoDebtRepay,
        bool _allowAutoSavingsWithdraw,
        bool _allowAutoDebtRepay
    ) internal {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationLimits(address(_account), _maxAutoBufferRestore, _maxAutoDebtRepay);
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationCapabilities(address(_account), _allowAutoSavingsWithdraw, _allowAutoDebtRepay);
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        return _defaultConfig(_SAVINGS_VAULT);
    }

    function _defaultConfig(address _approvedDestination)
        internal
        pure
        returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config)
    {
        address[] memory _destinations = new address[](1);
        _destinations[0] = _approvedDestination;

        uint256[] memory _caps = new uint256[](1);
        _caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _OPERATOR,
            approver: _APPROVER,
            liquidityBuffer: 200 ether,
            approvalThreshold: 100 ether,
            warningCollateralRatioBps: 18_000,
            criticalCollateralRatioBps: 15_000,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}
