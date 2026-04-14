// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {SavingsVaultAdapter} from "../../src/adapters/SavingsVaultAdapter.sol";
import {TreasuryAccount} from "../../src/core/TreasuryAccount.sol";
import {TreasuryAccountFactory} from "../../src/core/TreasuryAccountFactory.sol";
import {TreasuryPolicyEngine} from "../../src/core/TreasuryPolicyEngine.sol";
import {IMUSDSavingsVault} from "../../src/interfaces/IMUSDSavingsVault.sol";
import {ITreasuryPolicyEngine} from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract MockMUSDSavingsVault is IMUSDSavingsVault {
    uint256 public totalAssets;
    uint256 public totalShares;
    uint256 public lastDepositAssets;
    address public lastDepositReceiver;
    uint256 public lastWithdrawAssets;
    address public lastWithdrawReceiver;
    address public lastWithdrawOwner;

    function deposit(uint256 _assets, address _receiver) external returns (uint256 shares) {
        totalAssets += _assets;
        totalShares += _assets;
        lastDepositAssets = _assets;
        lastDepositReceiver = _receiver;
        shares = _assets;
    }

    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256 shares) {
        totalAssets -= _assets;
        totalShares -= _assets;
        lastWithdrawAssets = _assets;
        lastWithdrawReceiver = _receiver;
        lastWithdrawOwner = _owner;
        shares = _assets;
    }
}

contract SavingsVaultAdapterTest is Test {
    address internal constant TREASURY_ADMIN = address(0xA11CE);
    address internal constant OPERATOR = address(0xB0B);
    address internal constant APPROVER = address(0xCAFE);

    TreasuryPolicyEngine internal policyEngine;
    TreasuryAccountFactory internal factory;
    MockMUSDSavingsVault internal mockSavingsVault;
    SavingsVaultAdapter internal savingsVaultAdapter;
    TreasuryAccount internal treasuryAccount;

    function setUp() external {
        policyEngine = new TreasuryPolicyEngine();
        factory = new TreasuryAccountFactory(policyEngine);
        mockSavingsVault = new MockMUSDSavingsVault();
        savingsVaultAdapter = new SavingsVaultAdapter(mockSavingsVault);

        treasuryAccount = TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.prank(TREASURY_ADMIN);
        treasuryAccount.setAllocationAdapter(address(savingsVaultAdapter));

        vm.prank(TREASURY_ADMIN);
        treasuryAccount.recordBorrow(600 ether);
    }

    function testTreasuryAdminCanSetAllocationAdapter() external {
        TreasuryAccount account = TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.prank(TREASURY_ADMIN);
        account.setAllocationAdapter(address(savingsVaultAdapter));

        assertEq(account.allocationAdapter(), address(savingsVaultAdapter));
    }

    function testOperatorCanDepositIntoSavingsVaultWithinPolicy() external {
        vm.expectEmit(true, true, false, true);
        emit SavingsVaultAdapter.SavingsDepositRouted(address(treasuryAccount), OPERATOR, 100 ether, 100 ether);

        vm.prank(OPERATOR);
        uint256 shares = savingsVaultAdapter.deposit(treasuryAccount, 100 ether);

        assertEq(shares, 100 ether);
        assertEq(treasuryAccount.idleMUSD(), 500 ether);
        assertEq(treasuryAccount.destinationAllocations(address(mockSavingsVault)), 100 ether);
        assertEq(mockSavingsVault.totalAssets(), 100 ether);
        assertEq(mockSavingsVault.lastDepositAssets(), 100 ether);
        assertEq(mockSavingsVault.lastDepositReceiver(), address(treasuryAccount));
    }

    function testOperatorCannotDepositAboveApprovalThreshold() external {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(OPERATOR);
        savingsVaultAdapter.deposit(treasuryAccount, 150 ether);
    }

    function testApproverCanDepositAboveApprovalThreshold() external {
        vm.prank(APPROVER);
        savingsVaultAdapter.deposit(treasuryAccount, 150 ether);

        assertEq(treasuryAccount.idleMUSD(), 450 ether);
        assertEq(treasuryAccount.destinationAllocations(address(mockSavingsVault)), 150 ether);
    }

    function testWithdrawRestoresIdleTreasuryBalance() external {
        vm.prank(OPERATOR);
        savingsVaultAdapter.deposit(treasuryAccount, 100 ether);

        vm.expectEmit(true, true, false, true);
        emit SavingsVaultAdapter.SavingsWithdrawalRouted(address(treasuryAccount), OPERATOR, 40 ether, 40 ether);

        vm.prank(OPERATOR);
        uint256 shares = savingsVaultAdapter.withdraw(treasuryAccount, 40 ether);

        assertEq(shares, 40 ether);
        assertEq(treasuryAccount.idleMUSD(), 540 ether);
        assertEq(treasuryAccount.destinationAllocations(address(mockSavingsVault)), 60 ether);
        assertEq(mockSavingsVault.totalAssets(), 60 ether);
        assertEq(mockSavingsVault.lastWithdrawAssets(), 40 ether);
        assertEq(mockSavingsVault.lastWithdrawReceiver(), address(treasuryAccount));
        assertEq(mockSavingsVault.lastWithdrawOwner(), address(treasuryAccount));
    }

    function testAllocationAdapterRevertsWhenTreasuryAccountIsNotConfigured() external {
        TreasuryAccount unconfiguredAccount =
            TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.prank(TREASURY_ADMIN);
        unconfiguredAccount.recordBorrow(400 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, address(savingsVaultAdapter))
        );

        vm.prank(OPERATOR);
        savingsVaultAdapter.deposit(unconfiguredAccount, 50 ether);
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory destinations = new address[](1);
        destinations[0] = address(mockSavingsVault);

        uint256[] memory caps = new uint256[](1);
        caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: OPERATOR,
            approver: APPROVER,
            liquidityBuffer: 200 ether,
            approvalThreshold: 100 ether,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: destinations,
            destinationCaps: caps
        });
    }
}
