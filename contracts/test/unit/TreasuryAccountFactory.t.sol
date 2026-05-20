// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Test } from "forge-std/Test.sol";

import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";

contract TreasuryAccountFactoryTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _STRANGER = address(0xBAD);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(
            IERC20(_borrowerOperations.musdToken()), _policyEngine, address(new TreasuryAccount())
        );
    }

    function test_SetTreasuryAdminApproval_OwnerCanApproveTreasuryAdmin() public {
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);

        assertTrue(_factory.approvedTreasuryAdmins(_TREASURY_ADMIN));
    }

    function test_DeployTreasuryAccount_ApprovedTreasuryAdminCanSelfDeploy() public {
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);

        vm.prank(_TREASURY_ADMIN);
        address _treasuryAccount = _factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig());

        assertTrue(_factory.isTreasuryAccount(_treasuryAccount));
    }

    function test_DeployTreasuryAccount_OwnerCanDeployForApprovedTreasuryAdmin() public {
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);

        address _treasuryAccount = _factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig());

        assertTrue(_factory.isTreasuryAccount(_treasuryAccount));
    }

    function test_DeployTreasuryAccount_UnapprovedTreasuryAdminReverts() public {
        vm.prank(_TREASURY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryAccountFactory.TreasuryAdminNotApproved.selector, _TREASURY_ADMIN)
        );
        _factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig());
    }

    function test_DeployTreasuryAccount_UnauthorizedDeployerReverts() public {
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);

        vm.prank(_STRANGER);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryAccountFactory.UnauthorizedDeployer.selector, _STRANGER, _TREASURY_ADMIN)
        );
        _factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig());
    }

    function test_DeployTreasuryAccount_PausedFactoryReverts() public {
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _factory.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        _factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig());
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(0xD00D);

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
