// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { SavingsVaultAdapter } from "../../src/adapters/SavingsVaultAdapter.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { IMUSDSavingsVault } from "../../src/interfaces/IMUSDSavingsVault.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";

contract MockWorkflowSavingsVault is IMUSDSavingsVault {
    uint256 public totalAssets;
    uint256 public totalShares;

    function deposit(uint256 _assets, address) external returns (uint256 shares) {
        totalAssets += _assets;
        totalShares += _assets;
        shares = _assets;
    }

    function withdraw(uint256 _assets, address, address) external returns (uint256 shares) {
        totalAssets -= _assets;
        totalShares -= _assets;
        shares = _assets;
    }
}

contract TreasuryWorkflowIntegrationTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockWorkflowSavingsVault internal _savingsVault;
    SavingsVaultAdapter internal _savingsVaultAdapter;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(_policyEngine);
        _borrowerOperations = new MockBorrowerOperations();
        _savingsVault = new MockWorkflowSavingsVault();
        _savingsVaultAdapter = new SavingsVaultAdapter(_savingsVault);

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationAdapter(address(_savingsVaultAdapter));
    }

    function test_TreasuryWorkflow_OpenAllocateRepayWithdrawAndClose() public {
        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _savingsVaultAdapter.deposit(_treasuryAccount, 100 ether);

        vm.prank(_OPERATOR);
        _treasuryAccount.repayMUSD(50 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _treasuryAccount.withdrawCollateral(1 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _savingsVaultAdapter.withdraw(_treasuryAccount, 100 ether);

        vm.prank(_APPROVER);
        _treasuryAccount.closeTrove();

        assertFalse(_treasuryAccount.positionActive());
        assertEq(_treasuryAccount.idleMUSD(), 0);
        assertEq(_treasuryAccount.idleBTC(), 6 ether);
        assertEq(_treasuryAccount.positionCollateral(), 0);
        assertEq(_treasuryAccount.positionDebtPrincipal(), 0);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 0);
        assertEq(_savingsVault.totalAssets(), 0);
        assertEq(_borrowerOperations.totalCollateral(), 0);
        assertEq(_borrowerOperations.totalDebtPrincipal(), 0);
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
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}
