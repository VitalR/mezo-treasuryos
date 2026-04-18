// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../../src/adapters/MUSDSavingsRateHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryAutomationExecutor } from "../../src/core/TreasuryAutomationExecutor.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDSavingsRate } from "../helpers/MockMUSDSavingsRate.sol";

contract TreasuryAutomationExecutorTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _TREASURY_APPROVER = address(0xCAFE);
    address internal constant _TREASURY_OPERATOR = address(0xB0B);
    address internal constant _AUTOMATION_OPERATOR = address(0xA700);
    address internal constant _STRANGER = address(0xBAD);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    MockBorrowerOperations internal _borrowerOperations;
    TreasuryAccountFactory internal _factory;
    MockMUSDSavingsRate internal _savingsVault;
    AllocationRouter internal _allocationRouter;
    MUSDSavingsRateHandler internal _savingsHandler;
    TreasuryAutomationExecutor internal _automationExecutor;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(IERC20(_borrowerOperations.musdToken()), _policyEngine);
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _savingsVault = new MockMUSDSavingsRate(_borrowerOperations.musdTokenContract());
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _savingsHandler = new MUSDSavingsRateHandler(_savingsVault, address(_allocationRouter));
        _automationExecutor = new TreasuryAutomationExecutor(_TREASURY_ADMIN);

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_TREASURY_APPROVER, 50 ether);
        vm.deal(_TREASURY_OPERATOR, 50 ether);
        vm.deal(_AUTOMATION_OPERATOR, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.startPrank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));
        _treasuryAccount.setAllocationRouter(address(_allocationRouter));
        _allocationRouter.setHandler(address(_savingsVault), _savingsHandler);
        _policyEngine.updateAutomationExecutor(address(_treasuryAccount), address(_automationExecutor));
        _policyEngine.updateAutomationLimits(address(_treasuryAccount), 80 ether, 90 ether);
        _policyEngine.updateAutomationCapabilities(address(_treasuryAccount), true, true);
        _automationExecutor.setAutomationOperator(_AUTOMATION_OPERATOR, true);
        vm.stopPrank();
    }

    function test_RestoreBufferFromSavings_AuthorizedOperatorExecutesWorkflow() public {
        vm.prank(_TREASURY_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_TREASURY_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_savingsVault), 350 ether);

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.disburseMUSD(address(0xABCD), 120 ether);

        vm.prank(_AUTOMATION_OPERATOR);
        uint256 _restoredAmount =
            _automationExecutor.restoreBufferFromSavings(_treasuryAccount, address(_savingsVault), 80 ether);

        assertEq(_restoredAmount, 70 ether);
        assertEq(_treasuryAccount.idleMUSD(), 200 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 280 ether);
    }

    function test_DeRiskByRepayingFromSleeve_AuthorizedOperatorExecutesWorkflow() public {
        vm.prank(_TREASURY_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_TREASURY_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_savingsVault), 220 ether);

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.disburseMUSD(address(0xABCD), 250 ether);

        vm.prank(_AUTOMATION_OPERATOR);
        (uint256 _actualWithdrawAmount, uint256 _actualRepaidAmount) = _automationExecutor.deRiskByRepayingFromSleeve(
            _treasuryAccount, address(_savingsVault), 120 ether, 90 ether, _UPPER_HINT, _LOWER_HINT
        );

        assertEq(_actualWithdrawAmount, 120 ether);
        assertEq(_actualRepaidAmount, 90 ether);
        assertEq(_treasuryAccount.idleMUSD(), 160 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 100 ether);
        assertEq(_treasuryAccount.positionTotalDebt(), 510 ether);
    }

    function test_RestoreBufferFromSavings_UnauthorizedCallerReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryAutomationExecutor.UnauthorizedAutomationCaller.selector, _STRANGER)
        );

        vm.prank(_STRANGER);
        _automationExecutor.restoreBufferFromSavings(_treasuryAccount, address(_savingsVault), 50 ether);
    }

    function test_DeRiskByRepayingFromSleeve_PausedExecutorReverts() public {
        vm.prank(_TREASURY_ADMIN);
        _automationExecutor.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        vm.prank(_AUTOMATION_OPERATOR);
        _automationExecutor.deRiskByRepayingFromSleeve(
            _treasuryAccount, address(_savingsVault), 120 ether, 90 ether, _UPPER_HINT, _LOWER_HINT
        );
    }

    function test_SetAutomationOperator_OwnerUpdatesAuthorization() public {
        vm.prank(_TREASURY_ADMIN);
        _automationExecutor.setAutomationOperator(_STRANGER, true);

        assertTrue(_automationExecutor.automationOperators(_STRANGER));
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_savingsVault);

        uint256[] memory _caps = new uint256[](1);
        _caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _TREASURY_OPERATOR,
            approver: _TREASURY_APPROVER,
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
