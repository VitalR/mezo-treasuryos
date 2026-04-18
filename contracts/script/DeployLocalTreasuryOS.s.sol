// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AllocationRouter } from "../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../src/adapters/MUSDSavingsRateHandler.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../src/core/TreasuryPolicyEngine.sol";
import { ExternalMUSDSavingsRateMock } from "../src/external/ExternalMUSDSavingsRateMock.sol";
import { IAllocationHandler } from "../src/interfaces/IAllocationHandler.sol";
import { ITreasuryPolicyEngine } from "../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../test/helpers/MockBorrowerOperations.sol";
import { MockMUSDToken } from "../test/helpers/MockMUSDToken.sol";

/// @title DeployLocalTreasuryOS
/// @notice Deploys a simplified TreasuryOS stack to Anvil using local mock Mezo components.
contract DeployLocalTreasuryOS is Script {
    string internal constant DEFAULT_ANVIL_MNEMONIC = "test test test test test test test test test test test junk";

    uint256 internal constant DEFAULT_LIQUIDITY_BUFFER = 500e18;
    uint256 internal constant DEFAULT_APPROVAL_THRESHOLD = 250e18;
    uint256 internal constant DEFAULT_WARNING_COLLATERAL_RATIO_BPS = 18_000;
    uint256 internal constant DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant DEFAULT_MAX_AUTO_BUFFER_RESTORE = 500e18;
    uint256 internal constant DEFAULT_MAX_AUTO_DEBT_REPAY = 250e18;
    uint256 internal constant DEFAULT_SAVINGS_CAP = 10_000e18;
    uint256 internal constant DEFAULT_OWNER_MUSD_SEED = 50_000e18;

    struct LocalConfig {
        uint256 deployerPrivateKey;
        uint256 treasuryOwnerPrivateKey;
        address deployer;
        address treasuryOwner;
        address treasuryApprover;
        address treasuryOperator;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
        uint256 warningCollateralRatioBps;
        uint256 criticalCollateralRatioBps;
        bool automationEnabled;
        address automationExecutor;
        uint256 maxAutoBufferRestore;
        uint256 maxAutoDebtRepay;
        bool allowAutoSavingsWithdraw;
        bool allowAutoDebtRepay;
        bool startPaused;
        uint256 savingsCap;
        uint256 ownerMUSDSeed;
        uint256 borrowingFee;
        uint256 gasCompensation;
        string manifestPath;
    }

    struct LocalArtifacts {
        address mockBorrowerOperations;
        address mockMUSDToken;
        address treasuryPolicyEngine;
        address treasuryAccountFactory;
        address allocationRouter;
        address savingsDestination;
        address musdSavingsRateHandler;
        address treasuryAccount;
    }

    error InvalidOwnerConfiguration(address treasuryOwner, address derivedOwner);

    function run() external returns (LocalArtifacts memory artifacts) {
        LocalConfig memory config = _loadConfig();

        console2.log("Deploying local TreasuryOS stack");
        console2.log("Deployer:", config.deployer);
        console2.log("Treasury owner:", config.treasuryOwner);
        console2.log("Treasury approver:", config.treasuryApprover);
        console2.log("Treasury operator:", config.treasuryOperator);

        artifacts = _deploy(config);
        _configureOwnerControlledState(config, artifacts);
        _writeManifest(config, artifacts);

        console2.log("Local TreasuryAccount:", artifacts.treasuryAccount);
        console2.log("Local manifest:", config.manifestPath);
    }

    function _loadConfig() internal view returns (LocalConfig memory config) {
        string memory mnemonic = vm.envOr("ANVIL_MNEMONIC", string(DEFAULT_ANVIL_MNEMONIC));

        uint256 defaultDeployerKey = vm.deriveKey(mnemonic, 0);
        uint256 defaultApproverKey = vm.deriveKey(mnemonic, 1);
        uint256 defaultOperatorKey = vm.deriveKey(mnemonic, 2);

        config.deployerPrivateKey = vm.envOr("ANVIL_DEPLOYER_PRIVATE_KEY", defaultDeployerKey);
        config.deployer = vm.addr(config.deployerPrivateKey);

        config.treasuryOwnerPrivateKey = vm.envOr("ANVIL_TREASURY_OWNER_PRIVATE_KEY", config.deployerPrivateKey);
        config.treasuryOwner = vm.envOr("ANVIL_TREASURY_OWNER", vm.addr(config.treasuryOwnerPrivateKey));
        config.treasuryApprover = vm.envOr("ANVIL_TREASURY_APPROVER", vm.addr(defaultApproverKey));
        config.treasuryOperator = vm.envOr("ANVIL_TREASURY_OPERATOR", vm.addr(defaultOperatorKey));

        if (vm.addr(config.treasuryOwnerPrivateKey) != config.treasuryOwner) {
            revert InvalidOwnerConfiguration(config.treasuryOwner, vm.addr(config.treasuryOwnerPrivateKey));
        }

        config.liquidityBuffer = vm.envOr("ANVIL_TREASURY_LIQUIDITY_BUFFER", DEFAULT_LIQUIDITY_BUFFER);
        config.approvalThreshold = vm.envOr("ANVIL_TREASURY_APPROVAL_THRESHOLD", DEFAULT_APPROVAL_THRESHOLD);
        config.warningCollateralRatioBps =
            vm.envOr("ANVIL_TREASURY_WARNING_COLLATERAL_RATIO_BPS", DEFAULT_WARNING_COLLATERAL_RATIO_BPS);
        config.criticalCollateralRatioBps =
            vm.envOr("ANVIL_TREASURY_CRITICAL_COLLATERAL_RATIO_BPS", DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS);
        config.automationEnabled = vm.envOr("ANVIL_TREASURY_AUTOMATION_ENABLED", true);
        config.automationExecutor = vm.envOr("ANVIL_TREASURY_AUTOMATION_EXECUTOR", address(0));
        config.maxAutoBufferRestore =
            vm.envOr("ANVIL_TREASURY_MAX_AUTO_BUFFER_RESTORE", DEFAULT_MAX_AUTO_BUFFER_RESTORE);
        config.maxAutoDebtRepay = vm.envOr("ANVIL_TREASURY_MAX_AUTO_DEBT_REPAY", DEFAULT_MAX_AUTO_DEBT_REPAY);
        config.allowAutoSavingsWithdraw = vm.envOr("ANVIL_TREASURY_ALLOW_AUTO_SAVINGS_WITHDRAW", true);
        config.allowAutoDebtRepay = vm.envOr("ANVIL_TREASURY_ALLOW_AUTO_DEBT_REPAY", true);
        config.startPaused = vm.envOr("ANVIL_TREASURY_START_PAUSED", false);
        config.savingsCap = vm.envOr("ANVIL_SAVINGS_CAP", DEFAULT_SAVINGS_CAP);
        config.ownerMUSDSeed = vm.envOr("ANVIL_OWNER_MUSD_SEED", DEFAULT_OWNER_MUSD_SEED);
        config.borrowingFee = vm.envOr("ANVIL_BORROWING_FEE", uint256(0));
        config.gasCompensation = vm.envOr("ANVIL_GAS_COMPENSATION", uint256(0));
        config.manifestPath = vm.envOr("ANVIL_DEPLOYMENT_MANIFEST_PATH", string("../deployments/anvil-demo.json"));
    }

    function _deploy(LocalConfig memory config) internal returns (LocalArtifacts memory artifacts) {
        vm.startBroadcast(config.deployerPrivateKey);

        MockBorrowerOperations mockBorrowerOperations = new MockBorrowerOperations();
        MockMUSDToken mockMUSDToken = mockBorrowerOperations.musdTokenContract();
        mockBorrowerOperations.setBorrowingFee(config.borrowingFee);
        mockBorrowerOperations.setGasCompensation(config.gasCompensation);

        ExternalMUSDSavingsRateMock savingsDestination =
            new ExternalMUSDSavingsRateMock(config.treasuryOwner, IERC20(address(mockMUSDToken)));
        TreasuryPolicyEngine treasuryPolicyEngine = new TreasuryPolicyEngine();
        TreasuryAccountFactory treasuryAccountFactory =
            new TreasuryAccountFactory(IERC20(address(mockMUSDToken)), treasuryPolicyEngine);
        AllocationRouter allocationRouter = new AllocationRouter(config.treasuryOwner);
        MUSDSavingsRateHandler musdSavingsRateHandler =
            new MUSDSavingsRateHandler(savingsDestination, address(allocationRouter));

        address[] memory approvedDestinations = new address[](1);
        approvedDestinations[0] = address(savingsDestination);

        uint256[] memory destinationCaps = new uint256[](1);
        destinationCaps[0] = config.savingsCap;

        ITreasuryPolicyEngine.AccountPolicyConfig memory policyConfig = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: config.treasuryOperator,
            approver: config.treasuryApprover,
            liquidityBuffer: config.liquidityBuffer,
            approvalThreshold: config.approvalThreshold,
            warningCollateralRatioBps: config.warningCollateralRatioBps,
            criticalCollateralRatioBps: config.criticalCollateralRatioBps,
            automationEnabled: config.automationEnabled,
            startPaused: config.startPaused,
            approvedDestinations: approvedDestinations,
            destinationCaps: destinationCaps
        });

        address treasuryAccount = treasuryAccountFactory.deployTreasuryAccount(config.treasuryOwner, policyConfig);

        mockMUSDToken.mint(config.treasuryOwner, config.ownerMUSDSeed);

        vm.stopBroadcast();

        artifacts.mockBorrowerOperations = address(mockBorrowerOperations);
        artifacts.mockMUSDToken = address(mockMUSDToken);
        artifacts.treasuryPolicyEngine = address(treasuryPolicyEngine);
        artifacts.treasuryAccountFactory = address(treasuryAccountFactory);
        artifacts.allocationRouter = address(allocationRouter);
        artifacts.savingsDestination = address(savingsDestination);
        artifacts.musdSavingsRateHandler = address(musdSavingsRateHandler);
        artifacts.treasuryAccount = treasuryAccount;
    }

    function _configureOwnerControlledState(LocalConfig memory config, LocalArtifacts memory artifacts) internal {
        vm.startBroadcast(config.treasuryOwnerPrivateKey);

        AllocationRouter(artifacts.allocationRouter)
            .setHandler(artifacts.savingsDestination, IAllocationHandler(artifacts.musdSavingsRateHandler));
        TreasuryAccount(payable(artifacts.treasuryAccount)).setBorrowerOperations(artifacts.mockBorrowerOperations);
        TreasuryAccount(payable(artifacts.treasuryAccount)).setAllocationRouter(artifacts.allocationRouter);
        TreasuryPolicyEngine(artifacts.treasuryPolicyEngine)
            .updateAutomationLimits(artifacts.treasuryAccount, config.maxAutoBufferRestore, config.maxAutoDebtRepay);
        TreasuryPolicyEngine(artifacts.treasuryPolicyEngine)
            .updateAutomationCapabilities(
                artifacts.treasuryAccount, config.allowAutoSavingsWithdraw, config.allowAutoDebtRepay
            );

        if (config.automationExecutor != address(0)) {
            TreasuryPolicyEngine(artifacts.treasuryPolicyEngine)
                .updateAutomationExecutor(artifacts.treasuryAccount, config.automationExecutor);
        }

        vm.stopBroadcast();
    }

    function _writeManifest(LocalConfig memory config, LocalArtifacts memory artifacts) internal {
        string memory actorsJson = _buildActorsJson(config);
        string memory contractsJson = _buildContractsJson(artifacts);
        string memory treasuryScenarioJson = _buildTreasuryScenarioJson(config);

        string memory json = string.concat(
            "{",
            '"manifestVersion":1,',
            '"scenario":"anvil-demo",',
            '"network":{"name":"Anvil Local","chainId":',
            vm.toString(block.chainid),
            "},",
            '"actors":',
            actorsJson,
            ",",
            '"contracts":',
            contractsJson,
            ",",
            '"treasuryScenario":',
            treasuryScenarioJson,
            "}"
        );

        vm.writeJson(json, config.manifestPath);
    }

    function _buildActorsJson(LocalConfig memory config) internal view returns (string memory) {
        return string.concat(
            '{"deployer":"',
            vm.toString(config.deployer),
            '","treasuryOwner":"',
            vm.toString(config.treasuryOwner),
            '","treasuryApprover":"',
            vm.toString(config.treasuryApprover),
            '","treasuryOperator":"',
            vm.toString(config.treasuryOperator),
            '"}'
        );
    }

    function _buildContractsJson(LocalArtifacts memory artifacts) internal view returns (string memory) {
        return string.concat(
            '{"mockBorrowerOperations":"',
            vm.toString(artifacts.mockBorrowerOperations),
            '","mockMUSDToken":"',
            vm.toString(artifacts.mockMUSDToken),
            '","treasuryPolicyEngine":"',
            vm.toString(artifacts.treasuryPolicyEngine),
            '","treasuryAccountFactory":"',
            vm.toString(artifacts.treasuryAccountFactory),
            '","allocationRouter":"',
            vm.toString(artifacts.allocationRouter),
            '","savingsDestination":"',
            vm.toString(artifacts.savingsDestination),
            '","musdSavingsRateHandler":"',
            vm.toString(artifacts.musdSavingsRateHandler),
            '","treasuryAccount":"',
            vm.toString(artifacts.treasuryAccount),
            '"}'
        );
    }

    function _buildTreasuryScenarioJson(LocalConfig memory config) internal view returns (string memory) {
        return string.concat(
            '{"liquidityBuffer":"',
            vm.toString(config.liquidityBuffer),
            '","approvalThreshold":"',
            vm.toString(config.approvalThreshold),
            '","savingsCap":"',
            vm.toString(config.savingsCap),
            '","ownerMUSDSeed":"',
            vm.toString(config.ownerMUSDSeed),
            '"}'
        );
    }
}
