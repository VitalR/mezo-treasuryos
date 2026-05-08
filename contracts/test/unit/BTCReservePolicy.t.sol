// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { BTCReservePolicy } from "../../src/core/BTCReservePolicy.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract BTCReservePolicyTest is Test {
    address internal constant _TREASURY = address(0xA11CE);
    address internal constant _ADMIN = address(0xAD11);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _SLEEVE = address(0x515E);
    address internal constant _DIRECTIONAL_SLEEVE = address(0xD1A1);
    address internal constant _SPECULATIVE_SLEEVE = address(0x5FEC);

    TreasuryPolicyEngine internal _treasuryPolicyEngine;
    BTCReservePolicy internal _btcPolicy;

    function setUp() public {
        _treasuryPolicyEngine = new TreasuryPolicyEngine();
        _treasuryPolicyEngine.setFactory(address(this));
        _treasuryPolicyEngine.initializeAccount(_TREASURY, _ADMIN, _accountPolicyConfig());
        _btcPolicy = new BTCReservePolicy(_treasuryPolicyEngine);
    }

    function test_ConfigureBTCReservePolicy_AdminConfiguresPolicyAndBuckets() public {
        vm.startPrank(_ADMIN);
        _btcPolicy.configureBTCReservePolicy(_TREASURY, _defaultBTCPolicy());
        _btcPolicy.updateBTCReserveBuckets(_TREASURY, _defaultBuckets());
        vm.stopPrank();

        assertEq(_btcPolicy.availableBTCForYield(_TREASURY), 1 ether);
        assertEq(_btcPolicy.totalAccountedBTC(_TREASURY), 11 ether);
    }

    function test_ConfigureBTCReservePolicy_UnauthorizedCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(BTCReservePolicy.UnauthorizedActor.selector, _TREASURY, address(this)));

        _btcPolicy.configureBTCReservePolicy(_TREASURY, _defaultBTCPolicy());
    }

    function test_PreviewBTCAllocation_AllowsBTCCorrelatedSleeveWithApprovalRequired() public {
        _configureDefaultState();

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.5 ether);

        assertTrue(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.Allowed));
        assertEq(_preview.availableBTC, 1 ether);
        assertEq(_preview.projectedYieldActiveBTC, 1 ether);
        assertTrue(_preview.requiredApproval);
        assertEq(uint8(_preview.requiredApprovalLevel), uint8(BTCReservePolicy.BTCApprovalLevel.MULTISIG));
    }

    function test_PreviewBTCAllocation_BlocksInsufficientIdleReserve() public {
        _configureDefaultState();

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 1.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.InsufficientIdleBTCReserve));
    }

    function test_PreviewBTCAllocation_BlocksEmergencyReserveShortfall() public {
        _configureDefaultState();

        BTCReservePolicy.BTCReserveBuckets memory _buckets = _defaultBuckets();
        _buckets.emergencyBTCReserve = 0.25 ether;

        vm.prank(_ADMIN);
        _btcPolicy.updateBTCReserveBuckets(_TREASURY, _buckets);

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.EmergencyReserveShortfall));
    }

    function test_PreviewBTCAllocation_BlocksTotalYieldCap() public {
        _configureDefaultState();

        BTCReservePolicy.BTCReservePolicyConfig memory _policy = _defaultBTCPolicy();
        _policy.maxYieldBTCBps = 1000;
        BTCReservePolicy.BTCReserveBuckets memory _buckets = _defaultBuckets();
        _buckets.yieldActiveBTC = 1 ether;

        vm.startPrank(_ADMIN);
        _btcPolicy.configureBTCReservePolicy(_TREASURY, _policy);
        _btcPolicy.updateBTCReserveBuckets(_TREASURY, _buckets);
        vm.stopPrank();

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.5 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.TotalYieldCapExceeded));
    }

    function test_PreviewBTCAllocation_BlocksPerSleeveCap() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.updateBTCSleeveExposure(_TREASURY, _SLEEVE, 0.9 ether);

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.25 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.PerSleeveCapExceeded));
    }

    function test_PreviewBTCAllocation_BlocksDirectionalCap() public {
        _configureDefaultState();

        vm.startPrank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _DIRECTIONAL_SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_DIRECTIONAL_LP,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG_WITH_RISK_OVERRIDE
            })
        );
        _btcPolicy.updateBTCDirectionalExposure(_TREASURY, 0.45 ether);
        vm.stopPrank();

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _DIRECTIONAL_SLEEVE, 0.2 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.DirectionalCapExceeded));
    }

    function test_PreviewBTCAllocation_BlocksSpeculativeSleeve() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SPECULATIVE_SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.SPECULATIVE,
                enabled: true,
                sleeveCapBps: 100,
                assetDepegBps: 0,
                withdrawalDelaySeconds: 30 days,
                swapPriceImpactBps: 0,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.DISABLED
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SPECULATIVE_SLEEVE, 0.01 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.SpeculativeDisabled));
    }

    function test_RecordBTCAllocationPreview_OperatorCanEmitPolicyDecisionWithoutMovingFunds() public {
        _configureDefaultState();

        vm.prank(_OPERATOR);
        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.recordBTCAllocationPreview(_TREASURY, _SLEEVE, 0.5 ether);

        assertTrue(_preview.allowed);
        assertEq(_btcPolicy.availableBTCForYield(_TREASURY), 1 ether);
    }

    function test_PreviewBTCAllocation_BlocksCorrelatedSleeveWithoutMultisigApproval() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.APPROVER
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.ApprovalLevelTooLow));
    }

    function test_PreviewBTCAllocation_BlocksDisabledApprovalLevel() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.DISABLED
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.ApprovalLevelDisabled));
    }

    function test_PreviewBTCAllocation_BlocksDirectionalSleeveWithoutRiskOverride() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _DIRECTIONAL_SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_DIRECTIONAL_LP,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _DIRECTIONAL_SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.ApprovalLevelTooLow));
    }

    function test_PreviewBTCAllocation_BlocksPriceImpactAbovePolicy() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 600,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.SwapPriceImpactExceeded));
    }

    function test_PreviewBTCAllocation_BlocksSlippageAbovePolicy() public {
        _configureDefaultState();

        vm.prank(_ADMIN);
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 150,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
            })
        );

        BTCReservePolicy.BTCAllocationPreview memory _preview =
            _btcPolicy.previewBTCAllocation(_TREASURY, _SLEEVE, 0.1 ether);

        assertFalse(_preview.allowed);
        assertEq(uint8(_preview.reason), uint8(BTCReservePolicy.BTCAllocationDecisionCode.SlippageExceeded));
    }

    function _configureDefaultState() internal {
        vm.startPrank(_ADMIN);
        _btcPolicy.configureBTCReservePolicy(_TREASURY, _defaultBTCPolicy());
        _btcPolicy.updateBTCReserveBuckets(_TREASURY, _defaultBuckets());
        _btcPolicy.configureBTCSleeve(
            _TREASURY,
            _SLEEVE,
            BTCReservePolicy.BTCSleeveConfig({
                riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
                enabled: true,
                sleeveCapBps: 1000,
                assetDepegBps: 20,
                withdrawalDelaySeconds: 1 days,
                swapPriceImpactBps: 100,
                slippageBps: 100,
                approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
            })
        );
        vm.stopPrank();
    }

    function _defaultBTCPolicy() internal pure returns (BTCReservePolicy.BTCReservePolicyConfig memory config) {
        config = BTCReservePolicy.BTCReservePolicyConfig({
            minIdleBTCReserve: 1 ether,
            emergencyBTCReserve: 0.5 ether,
            maxYieldBTCBps: 3000,
            maxPerSleeveBTCBps: 1500,
            maxDirectionalBTCBps: 500,
            maxBTCAssetDepegBps: 100,
            maxSwapPriceImpactBps: 500,
            maxSlippageBps: 100,
            collateralWarningCRBps: 0,
            btcYieldPaused: false,
            initialized: false
        });
    }

    function _defaultBuckets() internal pure returns (BTCReservePolicy.BTCReserveBuckets memory buckets) {
        buckets = BTCReservePolicy.BTCReserveBuckets({
            idleBTCReserve: 2 ether,
            collateralBTC: 8 ether,
            emergencyBTCReserve: 0.5 ether,
            yieldActiveBTC: 0.5 ether,
            pendingWithdrawBTC: 0
        });
    }

    function _accountPolicyConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](0);
        uint256[] memory _caps = new uint256[](0);

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
