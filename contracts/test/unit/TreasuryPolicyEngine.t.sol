// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";

contract TreasuryPolicyEngineTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _AUTOMATION_EXECUTOR = address(0xA700);
    address internal constant _SAVINGS_VAULT = address(0xD00D);
    address internal constant _NEW_SLEEVE = address(0xF00D);
    address internal constant _STRANGER = address(0xBAD);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    TreasuryAccount internal _account;
    MockBorrowerOperations internal _borrowerOperations;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(
            IERC20(_borrowerOperations.musdToken()), _policyEngine, address(new TreasuryAccount())
        );
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _account = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));
    }

    function test_UpdateAutomationExecutor_TreasuryAdminUpdatesExecutor() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);

        (address _executor,,,,) = _policyEngine.getAccountAutomationPolicy(address(_account));

        assertEq(_executor, _AUTOMATION_EXECUTOR);
    }

    function test_UpdateAutomationEnabled_TreasuryAdminDisablesAutomation() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationEnabled(address(_account), false);

        (,,,,, bool _automationEnabled,,) = _policyEngine.getAccountPolicy(address(_account));

        assertFalse(_automationEnabled);
    }

    function test_UpdateAutomationThresholds_TreasuryAdminUpdatesRiskThresholds() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationThresholds(address(_account), 19_000, 16_000);

        (uint256 _warningCollateralRatioBps, uint256 _criticalCollateralRatioBps) =
            _policyEngine.getAccountRiskPolicy(address(_account));

        assertEq(_warningCollateralRatioBps, 19_000);
        assertEq(_criticalCollateralRatioBps, 16_000);
    }

    function test_UpdateAutomationLimits_TreasuryAdminUpdatesAutomationLimits() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationLimits(address(_account), 125 ether, 80 ether);

        (, uint256 _maxAutoBufferRestore, uint256 _maxAutoDebtRepay,,) =
            _policyEngine.getAccountAutomationPolicy(address(_account));

        assertEq(_maxAutoBufferRestore, 125 ether);
        assertEq(_maxAutoDebtRepay, 80 ether);
    }

    function test_UpdateAutomationCapabilities_TreasuryAdminUpdatesCapabilities() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationCapabilities(address(_account), true, true);

        (,,, bool _allowAutoSavingsWithdraw, bool _allowAutoDebtRepay) =
            _policyEngine.getAccountAutomationPolicy(address(_account));

        assertTrue(_allowAutoSavingsWithdraw);
        assertTrue(_allowAutoDebtRepay);
    }

    function test_UpdateRiskControls_TreasuryAdminUpdatesProjectedRiskPolicy() public {
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();

        vm.expectEmit(true, false, false, true);
        emit TreasuryPolicyEngine.RiskControlsUpdated(
            address(_account),
            _config.minOpenCollateralRatioBps,
            _config.targetCollateralRatioBps,
            _config.stressDropBps,
            _config.minPostStressCollateralRatioBps,
            _config.minIdleBTCReserve,
            _config.maxAutoIdleBTCTopUp,
            _config.allowAutomationBTCTopUp
        );

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        ITreasuryPolicyEngine.RiskControlConfig memory _stored = _policyEngine.getAccountRiskControls(address(_account));

        assertEq(_stored.minOpenCollateralRatioBps, 18_000);
        assertEq(_stored.targetCollateralRatioBps, 22_000);
        assertEq(_stored.stressDropBps, 2000);
        assertEq(_stored.minPostStressCollateralRatioBps, 14_000);
        assertEq(_stored.minIdleBTCReserve, 1 ether);
        assertEq(_stored.maxAutoIdleBTCTopUp, 0.5 ether);
        assertTrue(_stored.allowAutomationBTCTopUp);
    }

    function test_UpdateDestinationPolicy_TreasuryAdminApprovesAndRecapsSleeve() public {
        vm.expectEmit(true, true, true, true);
        emit TreasuryPolicyEngine.DestinationPolicyUpdated(
            address(_account), _NEW_SLEEVE, _TREASURY_ADMIN, true, 250 ether
        );

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateDestinationPolicy(address(_account), _NEW_SLEEVE, true, 250 ether);

        assertTrue(_policyEngine.isDestinationApproved(address(_account), _NEW_SLEEVE));
        assertEq(_policyEngine.allocationCap(address(_account), _NEW_SLEEVE), 250 ether);

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateDestinationPolicy(address(_account), _NEW_SLEEVE, true, 400 ether);

        assertEq(_policyEngine.allocationCap(address(_account), _NEW_SLEEVE), 400 ether);
    }

    function test_UpdateDestinationPolicy_TreasuryAdminRevokesSleeveAndClearsCap() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateDestinationPolicy(address(_account), _NEW_SLEEVE, true, 250 ether);

        vm.expectEmit(true, true, true, true);
        emit TreasuryPolicyEngine.DestinationPolicyUpdated(address(_account), _NEW_SLEEVE, _TREASURY_ADMIN, false, 0);

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateDestinationPolicy(address(_account), _NEW_SLEEVE, false, 250 ether);

        assertFalse(_policyEngine.isDestinationApproved(address(_account), _NEW_SLEEVE));
        assertEq(_policyEngine.allocationCap(address(_account), _NEW_SLEEVE), 0);
    }

    function test_UpdateDestinationPolicy_UnauthorizedCallerReverts() public {
        vm.prank(_STRANGER);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.UnauthorizedActor.selector, address(_account), _STRANGER)
        );
        _policyEngine.updateDestinationPolicy(address(_account), _NEW_SLEEVE, true, 250 ether);
    }

    function test_UpdateDestinationPolicy_InvalidDestinationReverts() public {
        vm.prank(_TREASURY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.InvalidDestination.selector, address(0)));
        _policyEngine.updateDestinationPolicy(address(_account), address(0), true, 250 ether);
    }

    function test_UpdateAutomationExecutor_UnauthorizedCallerReverts() public {
        vm.prank(_STRANGER);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.UnauthorizedActor.selector, address(_account), _STRANGER)
        );
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);
    }

    function test_UpdateAutomationThresholds_InvalidThresholdsRevert() public {
        vm.prank(_TREASURY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.InvalidRiskThresholds.selector, 15_000, 15_000));
        _policyEngine.updateAutomationThresholds(address(_account), 15_000, 15_000);
    }

    function test_UpdateRiskControls_InvalidConfigReverts() public {
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();
        _config.stressDropBps = 10_001;

        vm.prank(_TREASURY_ADMIN);
        vm.expectRevert(TreasuryPolicyEngine.InvalidRiskControlConfig.selector);
        _policyEngine.updateRiskControls(address(_account), _config);
    }

    function test_ValidateProjectedPosition_BlocksBelowMinimumCollateralRatio() public {
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ProjectedCollateralRatioTooLow.selector, 13_333, 18_000)
        );
        _policyEngine.validateProjectedPosition(address(_account), _TREASURY_ADMIN, 2 ether, 150 ether, 100 ether);
    }

    function test_ValidateProjectedPosition_BlocksPostStressShortfall() public {
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();
        _config.minOpenCollateralRatioBps = 0;
        _config.stressDropBps = 3000;
        _config.minPostStressCollateralRatioBps = 18_000;

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.PostStressCollateralRatioTooLow.selector, 17_500, 18_000)
        );
        _policyEngine.validateProjectedPosition(address(_account), _TREASURY_ADMIN, 2 ether, 80 ether, 100 ether);
    }

    function test_ValidateAutomationExecution_AuthorizedExecutorPasses() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);

        vm.prank(_AUTOMATION_EXECUTOR);
        _policyEngine.validateAutomationExecution(address(_account), _AUTOMATION_EXECUTOR);
    }

    function test_ValidateAutomationExecution_DisabledAutomationReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationEnabled(address(_account), false);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.AutomationDisabled.selector, address(_account)));
        _policyEngine.validateAutomationExecution(address(_account), _AUTOMATION_EXECUTOR);
    }

    function test_ValidateAutomationExecution_UnauthorizedExecutorReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);

        vm.prank(_STRANGER);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.UnauthorizedActor.selector, address(_account), _STRANGER)
        );
        _policyEngine.validateAutomationExecution(address(_account), _STRANGER);
    }

    function test_ValidateBufferRestore_AuthorizedExecutorPassesWithinLimit() public {
        _configureAutomation(120 ether, 80 ether, true, true);

        vm.prank(_AUTOMATION_EXECUTOR);
        _policyEngine.validateBufferRestore(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 100 ether);
    }

    function test_ValidateBufferRestore_TreasuryAdminPassesWithoutAutomationCapabilities() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.validateBufferRestore(address(_account), _TREASURY_ADMIN, _SAVINGS_VAULT, 100 ether);
    }

    function test_ValidateBufferRestore_DisabledCapabilityReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationLimits(address(_account), 120 ether, 80 ether);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.AutoSavingsWithdrawDisabled.selector, address(_account))
        );
        _policyEngine.validateBufferRestore(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 100 ether);
    }

    function test_ValidateBufferRestore_LimitExceededReverts() public {
        _configureAutomation(90 ether, 80 ether, true, true);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryPolicyEngine.AutomationLimitExceeded.selector, bytes32("BUFFER_RESTORE"), 100 ether, 90 ether
            )
        );
        _policyEngine.validateBufferRestore(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 100 ether);
    }

    function test_ValidateDeRiskRepayment_AuthorizedExecutorPassesWithinLimit() public {
        _configureAutomation(120 ether, 80 ether, true, true);

        vm.prank(_AUTOMATION_EXECUTOR);
        _policyEngine.validateDeRiskRepayment(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 75 ether);
    }

    function test_ValidateDeRiskRepayment_TreasuryAdminPassesWithoutAutomationCapabilities() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.validateDeRiskRepayment(address(_account), _TREASURY_ADMIN, _SAVINGS_VAULT, 75 ether);
    }

    function test_ValidateDeRiskRepayment_DisabledCapabilityReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationLimits(address(_account), 120 ether, 80 ether);
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationCapabilities(address(_account), true, false);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.AutoDebtRepayDisabled.selector, address(_account)));
        _policyEngine.validateDeRiskRepayment(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 75 ether);
    }

    function test_ValidateDeRiskRepayment_LimitExceededReverts() public {
        _configureAutomation(120 ether, 70 ether, true, true);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryPolicyEngine.AutomationLimitExceeded.selector, bytes32("DEBT_REPAY"), 75 ether, 70 ether
            )
        );
        _policyEngine.validateDeRiskRepayment(address(_account), _AUTOMATION_EXECUTOR, _SAVINGS_VAULT, 75 ether);
    }

    function test_ValidateIdleBTCTopUp_AutomationPassesWithinLimitAndReserveFloor() public {
        _configureAutomation(120 ether, 70 ether, true, true);
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        vm.prank(_AUTOMATION_EXECUTOR);
        _policyEngine.validateIdleBTCTopUp(address(_account), _AUTOMATION_EXECUTOR, 0.4 ether, 1.5 ether);
    }

    function test_ValidateIdleBTCTopUp_BlocksAutomationReserveFloorBreach() public {
        _configureAutomation(120 ether, 70 ether, true, true);
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.IdleBTCReserveBreached.selector, 0.9 ether, 1 ether)
        );
        _policyEngine.validateIdleBTCTopUp(address(_account), _AUTOMATION_EXECUTOR, 0.5 ether, 1.4 ether);
    }

    function test_ValidateIdleBTCTopUp_BlocksAutomationWhenDisabled() public {
        _configureAutomation(120 ether, 70 ether, true, true);
        ITreasuryPolicyEngine.RiskControlConfig memory _config = _riskControlConfig();
        _config.allowAutomationBTCTopUp = false;

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateRiskControls(address(_account), _config);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.AutoBTCTopUpDisabled.selector, address(_account)));
        _policyEngine.validateIdleBTCTopUp(address(_account), _AUTOMATION_EXECUTOR, 0.4 ether, 1.5 ether);
    }

    function test_ValidateAutomationExecution_PausedAccountReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _policyEngine.updateAutomationExecutor(address(_account), _AUTOMATION_EXECUTOR);

        vm.prank(_TREASURY_ADMIN);
        _policyEngine.setPause(address(_account), true);

        vm.prank(_AUTOMATION_EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.PolicyPaused.selector, address(_account)));
        _policyEngine.validateAutomationExecution(address(_account), _AUTOMATION_EXECUTOR);
    }

    function _configureAutomation(
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

    function _riskControlConfig() internal pure returns (ITreasuryPolicyEngine.RiskControlConfig memory config) {
        config = ITreasuryPolicyEngine.RiskControlConfig({
            minOpenCollateralRatioBps: 18_000,
            targetCollateralRatioBps: 22_000,
            stressDropBps: 2000,
            minPostStressCollateralRatioBps: 14_000,
            minIdleBTCReserve: 1 ether,
            maxAutoIdleBTCTopUp: 0.5 ether,
            allowAutomationBTCTopUp: true
        });
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = _SAVINGS_VAULT;

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
