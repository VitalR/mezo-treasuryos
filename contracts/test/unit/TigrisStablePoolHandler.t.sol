// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { TigrisStablePoolHandler } from "../../src/adapters/TigrisStablePoolHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDToken } from "../helpers/MockMUSDToken.sol";
import { MockTigrisBasicRouter } from "../helpers/MockTigrisBasicRouter.sol";
import { MockTigrisLPToken } from "../helpers/MockTigrisLPToken.sol";

contract TigrisStablePoolHandlerTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDToken internal _pairedStable;
    MockTigrisLPToken internal _poolToken;
    MockTigrisBasicRouter internal _router;
    AllocationRouter internal _allocationRouter;
    TigrisStablePoolHandler internal _handler;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(IERC20(_borrowerOperations.musdToken()), _policyEngine);
        _pairedStable = new MockMUSDToken();
        _poolToken = new MockTigrisLPToken();
        _router = new MockTigrisBasicRouter(_borrowerOperations.musdTokenContract(), _pairedStable, _poolToken);
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _handler = new TigrisStablePoolHandler(
            address(_allocationRouter),
            _router,
            address(_poolToken),
            IERC20(_borrowerOperations.musdToken()),
            IERC20(address(_pairedStable)),
            1 hours
        );

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationRouter(address(_allocationRouter));

        vm.prank(_TREASURY_ADMIN);
        _allocationRouter.setHandler(address(_poolToken), _handler);

        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_Deposit_OperatorRoutesIdleMUSDIntoTigrisStablePool() public {
        vm.prank(_OPERATOR);
        uint256 _liquidity = _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        assertEq(_liquidity, 100 ether);
        assertEq(_treasuryAccount.idleMUSD(), 500 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 100 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 100 ether);
        assertEq(_pairedStable.balanceOf(address(_treasuryAccount)), 0);
    }

    function test_Withdraw_OperatorUnwindsStablePoolBackToIdleMUSD() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        vm.prank(_OPERATOR);
        uint256 _liquidityBurned = _allocationRouter.withdraw(address(_treasuryAccount), address(_poolToken), 40 ether);

        assertEq(_liquidityBurned, 40 ether);
        assertEq(_treasuryAccount.idleMUSD(), 540 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 60 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 60 ether);
        assertEq(_pairedStable.balanceOf(address(_treasuryAccount)), 0);
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_poolToken);

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
