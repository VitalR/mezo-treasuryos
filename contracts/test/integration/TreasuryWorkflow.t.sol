// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

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

contract TreasuryWorkflowIntegrationTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDSavingsRate internal _savingsVault;
    AllocationRouter internal _allocationRouter;
    MUSDSavingsRateHandler internal _savingsVaultHandler;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(
            IERC20(_borrowerOperations.musdToken()), _policyEngine, address(new TreasuryAccount())
        );
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _savingsVault = new MockMUSDSavingsRate(_borrowerOperations.musdTokenContract());
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _savingsVaultHandler = new MUSDSavingsRateHandler(_savingsVault, address(_allocationRouter));

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationRouter(address(_allocationRouter));

        vm.prank(_TREASURY_ADMIN);
        _allocationRouter.setHandler(address(_savingsVault), _savingsVaultHandler);
    }

    function test_TreasuryWorkflow_OpenAllocateRepayWithdrawAndClose() public {
        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_savingsVault), 100 ether);

        vm.prank(_OPERATOR);
        _treasuryAccount.repayMUSD(50 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _treasuryAccount.withdrawCollateral(1 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _allocationRouter.withdraw(address(_treasuryAccount), address(_savingsVault), 100 ether);

        vm.prank(_APPROVER);
        _treasuryAccount.closeTrove();

        assertFalse(_treasuryAccount.positionActive());
        assertEq(_treasuryAccount.idleMUSD(), 0);
        assertEq(_treasuryAccount.idleBTC(), 6 ether);
        assertEq(_treasuryAccount.positionCollateral(), 0);
        assertEq(_treasuryAccount.positionTotalDebt(), 0);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 0);
        assertEq(_savingsVault.balanceOf(address(_treasuryAccount)), 0);
        assertEq(_borrowerOperations.totalCollateral(address(_treasuryAccount)), 0);
        assertEq(_borrowerOperations.totalDebt(address(_treasuryAccount)), 0);
    }

    function test_TreasuryWorkflow_RestoreBufferAndDeRiskThroughSavingsSleeve() public {
        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_savingsVault), 300 ether);

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.disburseMUSD(address(0xABCD), 150 ether);

        vm.prank(_TREASURY_ADMIN);
        uint256 _restoredAmount = _treasuryAccount.restoreLiquidityBuffer(address(_savingsVault), 60 ether);

        vm.prank(_TREASURY_ADMIN);
        (uint256 _actualWithdrawAmount, uint256 _actualRepaidAmount) = _treasuryAccount.withdrawFromDestinationAndRepay(
            address(_savingsVault), 140 ether, 100 ether, _UPPER_HINT, _LOWER_HINT
        );

        assertEq(_restoredAmount, 50 ether);
        assertEq(_actualWithdrawAmount, 140 ether);
        assertEq(_actualRepaidAmount, 100 ether);
        assertEq(_treasuryAccount.idleMUSD(), 240 ether);
        assertEq(_treasuryAccount.positionTotalDebt(), 500 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 110 ether);
        assertEq(_savingsVault.balanceOf(address(_treasuryAccount)), 110 ether);
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_savingsVault);

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
