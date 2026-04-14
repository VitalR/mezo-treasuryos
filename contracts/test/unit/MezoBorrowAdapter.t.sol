// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { MezoBorrowAdapter } from "../../src/adapters/MezoBorrowAdapter.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { IMezoBorrowOperations } from "../../src/interfaces/IMezoBorrowOperations.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";

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
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _SAVINGS_VAULT = address(0xD00D);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockMezoBorrowOperations internal _mockBorrowOperations;
    MezoBorrowAdapter internal _borrowAdapter;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(_policyEngine);
        _mockBorrowOperations = new MockMezoBorrowOperations();
        _borrowAdapter = new MezoBorrowAdapter(_mockBorrowOperations);

        _treasuryAccount = TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowAdapter(address(_borrowAdapter));
    }

    function test_SetBorrowAdapter_TreasuryAdminCanSetBorrowAdapter() public {
        TreasuryAccount _account = TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowAdapter(address(_borrowAdapter));

        assertEq(_account.borrowAdapter(), address(_borrowAdapter));
    }

    function test_OriginateBorrow_OperatorCanOriginateBorrowWithinApprovalThreshold() public {
        vm.expectEmit(true, true, false, true);
        emit MezoBorrowAdapter.BorrowOriginated(address(_treasuryAccount), _OPERATOR, 2 ether, 80 ether, 1);

        vm.prank(_OPERATOR);
        uint256 _positionId = _borrowAdapter.originateBorrow(_treasuryAccount, 2 ether, 80 ether);

        assertEq(_positionId, 1);
        assertEq(_treasuryAccount.idleMUSD(), 80 ether);
        assertEq(_mockBorrowOperations.lastOnBehalfOf(), address(_treasuryAccount));
        assertEq(_mockBorrowOperations.lastBTCAmount(), 2 ether);
        assertEq(_mockBorrowOperations.lastMUSDAmount(), 80 ether);
        assertEq(_mockBorrowOperations.lastRecipient(), address(_treasuryAccount));
    }

    function test_OriginateBorrow_OperatorCannotOriginateBorrowAboveApprovalThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _borrowAdapter.originateBorrow(_treasuryAccount, 2 ether, 150 ether);
    }

    function test_OriginateBorrow_ApproverCanOriginateBorrowAboveApprovalThreshold() public {
        vm.prank(_APPROVER);
        uint256 _positionId = _borrowAdapter.originateBorrow(_treasuryAccount, 2 ether, 150 ether);

        assertEq(_positionId, 1);
        assertEq(_treasuryAccount.idleMUSD(), 150 ether);
    }

    function test_OriginateBorrow_UnconfiguredTreasuryAccountReverts() public {
        TreasuryAccount _unconfiguredAccount =
            TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.expectRevert(abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, address(_borrowAdapter)));

        vm.prank(_OPERATOR);
        _borrowAdapter.originateBorrow(_unconfiguredAccount, 1 ether, 50 ether);
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
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}
