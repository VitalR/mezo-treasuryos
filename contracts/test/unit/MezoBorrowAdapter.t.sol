// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {MezoBorrowAdapter} from "../../src/adapters/MezoBorrowAdapter.sol";
import {TreasuryAccount} from "../../src/core/TreasuryAccount.sol";
import {TreasuryAccountFactory} from "../../src/core/TreasuryAccountFactory.sol";
import {TreasuryPolicyEngine} from "../../src/core/TreasuryPolicyEngine.sol";
import {IMezoBorrowOperations} from "../../src/interfaces/IMezoBorrowOperations.sol";
import {ITreasuryPolicyEngine} from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract MockMezoBorrowOperations is IMezoBorrowOperations {
    address public lastOnBehalfOf;
    uint256 public lastBTCAmount;
    uint256 public lastMUSDAmount;
    address public lastRecipient;
    uint256 public nextPositionId = 1;

    function depositAndBorrow(address _onBehalfOf, uint256 _btcAmount, uint256 _musdAmount, address _recipient)
        external
        returns (uint256 positionId)
    {
        lastOnBehalfOf = _onBehalfOf;
        lastBTCAmount = _btcAmount;
        lastMUSDAmount = _musdAmount;
        lastRecipient = _recipient;

        positionId = nextPositionId;
        nextPositionId += 1;
    }
}

contract MezoBorrowAdapterTest is Test {
    address internal constant TREASURY_ADMIN = address(0xA11CE);
    address internal constant OPERATOR = address(0xB0B);
    address internal constant APPROVER = address(0xCAFE);
    address internal constant SAVINGS_VAULT = address(0xD00D);

    TreasuryPolicyEngine internal policyEngine;
    TreasuryAccountFactory internal factory;
    MockMezoBorrowOperations internal mockBorrowOperations;
    MezoBorrowAdapter internal borrowAdapter;
    TreasuryAccount internal treasuryAccount;

    function setUp() external {
        policyEngine = new TreasuryPolicyEngine();
        factory = new TreasuryAccountFactory(policyEngine);
        mockBorrowOperations = new MockMezoBorrowOperations();
        borrowAdapter = new MezoBorrowAdapter(mockBorrowOperations);

        treasuryAccount = TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.prank(TREASURY_ADMIN);
        treasuryAccount.setBorrowAdapter(address(borrowAdapter));
    }

    function testTreasuryAdminCanSetBorrowAdapter() external {
        TreasuryAccount account = TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.prank(TREASURY_ADMIN);
        account.setBorrowAdapter(address(borrowAdapter));

        assertEq(account.borrowAdapter(), address(borrowAdapter));
    }

    function testOperatorCanOriginateBorrowWithinApprovalThreshold() external {
        vm.expectEmit(true, true, false, true);
        emit MezoBorrowAdapter.BorrowOriginated(address(treasuryAccount), OPERATOR, 2 ether, 80 ether, 1);

        vm.prank(OPERATOR);
        uint256 positionId = borrowAdapter.originateBorrow(treasuryAccount, 2 ether, 80 ether);

        assertEq(positionId, 1);
        assertEq(treasuryAccount.idleMUSD(), 80 ether);
        assertEq(mockBorrowOperations.lastOnBehalfOf(), address(treasuryAccount));
        assertEq(mockBorrowOperations.lastBTCAmount(), 2 ether);
        assertEq(mockBorrowOperations.lastMUSDAmount(), 80 ether);
        assertEq(mockBorrowOperations.lastRecipient(), address(treasuryAccount));
    }

    function testOperatorCannotOriginateBorrowAboveApprovalThreshold() external {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(OPERATOR);
        borrowAdapter.originateBorrow(treasuryAccount, 2 ether, 150 ether);
    }

    function testApproverCanOriginateBorrowAboveApprovalThreshold() external {
        vm.prank(APPROVER);
        uint256 positionId = borrowAdapter.originateBorrow(treasuryAccount, 2 ether, 150 ether);

        assertEq(positionId, 1);
        assertEq(treasuryAccount.idleMUSD(), 150 ether);
    }

    function testBorrowAdapterRevertsWhenTreasuryAccountIsNotConfigured() external {
        TreasuryAccount unconfiguredAccount =
            TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _defaultConfig()));

        vm.expectRevert(abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, address(borrowAdapter)));

        vm.prank(OPERATOR);
        borrowAdapter.originateBorrow(unconfiguredAccount, 1 ether, 50 ether);
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory destinations = new address[](1);
        destinations[0] = SAVINGS_VAULT;

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
