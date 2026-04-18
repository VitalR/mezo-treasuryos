// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AllocationRouter } from "../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../src/adapters/MUSDSavingsRateHandler.sol";
import { TigrisStablePoolHandler } from "../src/adapters/TigrisStablePoolHandler.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../src/core/TreasuryPolicyEngine.sol";
import { ExternalMUSDSavingsRateMock } from "../src/external/ExternalMUSDSavingsRateMock.sol";
import { IAllocationHandler } from "../src/interfaces/IAllocationHandler.sol";
import { IMUSDSavingsRate } from "../src/interfaces/IMUSDSavingsRate.sol";
import { ITigrisBasicRouter } from "../src/interfaces/ITigrisBasicRouter.sol";
import { ITreasuryPolicyEngine } from "../src/interfaces/ITreasuryPolicyEngine.sol";

/// @title DeployTreasuryOS
/// @notice Deploys a TreasuryOS demo stack on Mezo testnet and writes a deployment manifest.
contract DeployTreasuryOS is Script {
    uint256 internal constant DEFAULT_LIQUIDITY_BUFFER = 500e18;
    uint256 internal constant DEFAULT_APPROVAL_THRESHOLD = 250e18;
    uint256 internal constant DEFAULT_WARNING_COLLATERAL_RATIO_BPS = 18_000;
    uint256 internal constant DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant DEFAULT_MAX_AUTO_BUFFER_RESTORE = 500e18;
    uint256 internal constant DEFAULT_MAX_AUTO_DEBT_REPAY = 250e18;
    uint256 internal constant DEFAULT_SAVINGS_CAP = 10_000e18;
    uint256 internal constant DEFAULT_TIGRIS_CAP = 5000e18;
    uint256 internal constant DEFAULT_TIGRIS_DEADLINE_WINDOW = 15 minutes;

    struct DeploymentConfig {
        uint256 chainId;
        uint256 deployerPrivateKey;
        uint256 treasuryOwnerPrivateKey;
        address deployer;
        address treasuryOwner;
        address treasuryApprover;
        address treasuryOperator;
        address musdToken;
        address borrowerOperations;
        address savingsRate;
        address externalSavingsRateMock;
        bool deployExternalSavingsMock;
        address tigrisRouter;
        address tigrisMusdMusdcPool;
        address musdcToken;
        uint256 tigrisDeadlineWindow;
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
        uint256 tigrisCap;
        string manifestPath;
    }

    struct DeploymentArtifacts {
        address treasuryPolicyEngine;
        address treasuryAccountFactory;
        address allocationRouter;
        address musdSavingsRateHandler;
        address tigrisStablePoolHandler;
        address externalMusdSavingsRateMock;
        address treasuryAccount;
        address savingsDestination;
    }

    error InvalidAddress(string key);
    error InvalidOwnerConfiguration(address treasuryOwner, address derivedOwner);
    error MissingOwnerPrivateKey(address treasuryOwner);

    /// @notice Deploys the TreasuryOS demo stack and writes a deployment manifest.
    function run() external returns (DeploymentArtifacts memory artifacts) {
        DeploymentConfig memory config = _loadConfig();

        console2.log("Deploying TreasuryOS to chain ID:", block.chainid);
        console2.log("Deployer:", config.deployer);
        console2.log("Treasury owner:", config.treasuryOwner);

        artifacts = _deployCore(config);
        _configureOwnerControlledState(config, artifacts);
        _writeManifest(config, artifacts);

        console2.log("TreasuryPolicyEngine:", artifacts.treasuryPolicyEngine);
        console2.log("TreasuryAccountFactory:", artifacts.treasuryAccountFactory);
        console2.log("AllocationRouter:", artifacts.allocationRouter);
        console2.log("TreasuryAccount:", artifacts.treasuryAccount);
        console2.log("Manifest:", config.manifestPath);
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.chainId = vm.envOr("MEZO_CHAIN_ID", block.chainid);
        config.deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        config.deployer = vm.addr(config.deployerPrivateKey);
        config.treasuryOwner = vm.envAddress("TREASURY_OWNER");
        config.treasuryApprover = vm.envAddress("TREASURY_APPROVER");
        config.treasuryOperator = vm.envAddress("TREASURY_OPERATOR");
        config.musdToken = vm.envAddress("MEZO_MUSD_TOKEN");
        config.borrowerOperations = vm.envAddress("MEZO_BORROWER_OPERATIONS");
        config.savingsRate = vm.envOr("MEZO_MUSD_SAVINGS_RATE", address(0));
        config.externalSavingsRateMock = vm.envOr("EXTERNAL_MUSD_SAVINGS_RATE_MOCK", address(0));
        config.deployExternalSavingsMock = vm.envOr("DEPLOY_EXTERNAL_SAVINGS_MOCK", config.savingsRate == address(0));
        config.tigrisRouter = vm.envOr("MEZO_TIGRIS_ROUTER", address(0));
        config.tigrisMusdMusdcPool = vm.envOr("MEZO_TIGRIS_MUSD_MUSDC_POOL", address(0));
        config.musdcToken = vm.envOr("MEZO_MUSDC_TOKEN", address(0));
        config.tigrisDeadlineWindow = vm.envOr("TIGRIS_DEADLINE_WINDOW", DEFAULT_TIGRIS_DEADLINE_WINDOW);
        config.liquidityBuffer = vm.envOr("DEMO_TREASURY_LIQUIDITY_BUFFER", DEFAULT_LIQUIDITY_BUFFER);
        config.approvalThreshold = vm.envOr("DEMO_TREASURY_APPROVAL_THRESHOLD", DEFAULT_APPROVAL_THRESHOLD);
        config.warningCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_WARNING_COLLATERAL_RATIO_BPS", DEFAULT_WARNING_COLLATERAL_RATIO_BPS);
        config.criticalCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_CRITICAL_COLLATERAL_RATIO_BPS", DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS);
        config.automationEnabled = vm.envOr("DEMO_TREASURY_AUTOMATION_ENABLED", true);
        config.automationExecutor = vm.envOr("DEMO_TREASURY_AUTOMATION_EXECUTOR", address(0));
        config.maxAutoBufferRestore = vm.envOr("DEMO_TREASURY_MAX_AUTO_BUFFER_RESTORE", DEFAULT_MAX_AUTO_BUFFER_RESTORE);
        config.maxAutoDebtRepay = vm.envOr("DEMO_TREASURY_MAX_AUTO_DEBT_REPAY", DEFAULT_MAX_AUTO_DEBT_REPAY);
        config.allowAutoSavingsWithdraw = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_SAVINGS_WITHDRAW", true);
        config.allowAutoDebtRepay = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_DEBT_REPAY", true);
        config.startPaused = vm.envOr("DEMO_TREASURY_START_PAUSED", false);
        config.savingsCap = vm.envOr("DEMO_SAVINGS_CAP", DEFAULT_SAVINGS_CAP);
        config.tigrisCap = vm.envOr("DEMO_TIGRIS_CAP", DEFAULT_TIGRIS_CAP);
        config.manifestPath = vm.envOr("DEPLOYMENT_MANIFEST_PATH", string("../deployments/mezo-testnet-demo.json"));

        config.treasuryOwnerPrivateKey = vm.envOr("TREASURY_OWNER_PRIVATE_KEY", uint256(0));
        if (config.treasuryOwnerPrivateKey == 0) {
            if (config.treasuryOwner == config.deployer) {
                config.treasuryOwnerPrivateKey = config.deployerPrivateKey;
            } else {
                revert MissingOwnerPrivateKey(config.treasuryOwner);
            }
        }

        address derivedOwner = vm.addr(config.treasuryOwnerPrivateKey);
        if (derivedOwner != config.treasuryOwner) {
            revert InvalidOwnerConfiguration(config.treasuryOwner, derivedOwner);
        }

        if (config.treasuryOwner == address(0)) revert InvalidAddress("TREASURY_OWNER");
        if (config.treasuryApprover == address(0)) revert InvalidAddress("TREASURY_APPROVER");
        if (config.treasuryOperator == address(0)) revert InvalidAddress("TREASURY_OPERATOR");
        if (config.musdToken == address(0)) revert InvalidAddress("MEZO_MUSD_TOKEN");
        if (config.borrowerOperations == address(0)) revert InvalidAddress("MEZO_BORROWER_OPERATIONS");
    }

    function _deployCore(DeploymentConfig memory config) internal returns (DeploymentArtifacts memory artifacts) {
        vm.startBroadcast(config.deployerPrivateKey);

        TreasuryPolicyEngine treasuryPolicyEngine = new TreasuryPolicyEngine();
        TreasuryAccountFactory treasuryAccountFactory =
            new TreasuryAccountFactory(IERC20(config.musdToken), treasuryPolicyEngine);
        AllocationRouter allocationRouter = new AllocationRouter(config.treasuryOwner);

        artifacts.treasuryPolicyEngine = address(treasuryPolicyEngine);
        artifacts.treasuryAccountFactory = address(treasuryAccountFactory);
        artifacts.allocationRouter = address(allocationRouter);

        if (config.savingsRate != address(0)) {
            artifacts.savingsDestination = config.savingsRate;
        } else if (config.deployExternalSavingsMock) {
            if (config.externalSavingsRateMock == address(0)) {
                ExternalMUSDSavingsRateMock externalSavingsRateMock =
                    new ExternalMUSDSavingsRateMock(config.treasuryOwner, IERC20(config.musdToken));
                artifacts.externalMusdSavingsRateMock = address(externalSavingsRateMock);
                artifacts.savingsDestination = address(externalSavingsRateMock);
            } else {
                artifacts.externalMusdSavingsRateMock = config.externalSavingsRateMock;
                artifacts.savingsDestination = config.externalSavingsRateMock;
            }
        }

        if (artifacts.savingsDestination != address(0)) {
            MUSDSavingsRateHandler musdSavingsRateHandler =
                new MUSDSavingsRateHandler(IMUSDSavingsRate(artifacts.savingsDestination), artifacts.allocationRouter);
            artifacts.musdSavingsRateHandler = address(musdSavingsRateHandler);
        }

        if (
            config.tigrisRouter != address(0) && config.tigrisMusdMusdcPool != address(0)
                && config.musdcToken != address(0)
        ) {
            TigrisStablePoolHandler tigrisStablePoolHandler = new TigrisStablePoolHandler(
                artifacts.allocationRouter,
                ITigrisBasicRouter(config.tigrisRouter),
                config.tigrisMusdMusdcPool,
                IERC20(config.musdToken),
                IERC20(config.musdcToken),
                config.tigrisDeadlineWindow
            );

            artifacts.tigrisStablePoolHandler = address(tigrisStablePoolHandler);
        } else {
            console2.log("Skipping TigrisStablePoolHandler deployment: missing router, pool, or MEZO_MUSDC_TOKEN");
        }

        address[] memory approvedDestinations =
            _buildApprovedDestinations(artifacts.savingsDestination, artifacts.tigrisStablePoolHandler, config);
        uint256[] memory destinationCaps =
            _buildDestinationCaps(artifacts.savingsDestination, artifacts.tigrisStablePoolHandler, config);

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

        treasuryAccountFactory.setTreasuryAdminApproval(config.treasuryOwner, true);
        artifacts.treasuryAccount = treasuryAccountFactory.deployTreasuryAccount(config.treasuryOwner, policyConfig);

        vm.stopBroadcast();
    }

    function _configureOwnerControlledState(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
    {
        vm.startBroadcast(config.treasuryOwnerPrivateKey);

        if (artifacts.musdSavingsRateHandler != address(0) && artifacts.savingsDestination != address(0)) {
            AllocationRouter(artifacts.allocationRouter)
                .setHandler(artifacts.savingsDestination, IAllocationHandler(artifacts.musdSavingsRateHandler));
        }

        if (artifacts.tigrisStablePoolHandler != address(0) && config.tigrisMusdMusdcPool != address(0)) {
            AllocationRouter(artifacts.allocationRouter)
                .setHandler(config.tigrisMusdMusdcPool, IAllocationHandler(artifacts.tigrisStablePoolHandler));
        }

        TreasuryAccount(payable(artifacts.treasuryAccount)).setBorrowerOperations(config.borrowerOperations);
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

    function _buildApprovedDestinations(
        address _savingsDestination,
        address _tigrisStablePoolHandler,
        DeploymentConfig memory config
    ) internal pure returns (address[] memory destinations) {
        uint256 count;

        bool hasSavingsDestination = _savingsDestination != address(0);
        bool hasTigrisDestination = _tigrisStablePoolHandler != address(0);

        if (hasSavingsDestination) count++;
        if (hasTigrisDestination) count++;

        destinations = new address[](count);

        uint256 index;
        if (hasSavingsDestination) {
            destinations[index++] = _savingsDestination;
        }

        if (hasTigrisDestination) {
            destinations[index] = config.tigrisMusdMusdcPool;
        }
    }

    function _buildDestinationCaps(
        address _savingsDestination,
        address _tigrisStablePoolHandler,
        DeploymentConfig memory config
    ) internal pure returns (uint256[] memory caps) {
        uint256 count;
        if (_savingsDestination != address(0)) count++;
        if (_tigrisStablePoolHandler != address(0)) count++;

        caps = new uint256[](count);

        uint256 index;
        bool hasSavingsDestination = _savingsDestination != address(0);
        bool hasTigrisDestination = _tigrisStablePoolHandler != address(0);

        if (hasSavingsDestination) {
            caps[index++] = config.savingsCap;
        }

        if (hasTigrisDestination) {
            caps[index] = config.tigrisCap;
        }
    }

    function _writeManifest(DeploymentConfig memory config, DeploymentArtifacts memory artifacts) internal {
        string memory actorsJson = _buildActorsJson(config);
        string memory contractsJson = _buildContractsJson(artifacts);
        string memory referencesJson = _buildReferencesJson(config, artifacts);
        string memory treasuryScenarioJson = _buildTreasuryScenarioJson(config);

        string memory json = string.concat(
            "{",
            '"manifestVersion":1,',
            '"scenario":"mezo-testnet-demo",',
            '"network":{"name":"Mezo Testnet","chainId":',
            vm.toString(config.chainId),
            "},",
            '"chainIdObserved":',
            vm.toString(block.chainid),
            ",",
            '"actors":',
            actorsJson,
            ",",
            '"contracts":',
            contractsJson,
            ",",
            '"references":',
            referencesJson,
            ",",
            '"treasuryScenario":',
            treasuryScenarioJson,
            "}"
        );

        vm.writeJson(json, config.manifestPath);
    }

    function _buildActorsJson(DeploymentConfig memory config) internal view returns (string memory) {
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

    function _buildContractsJson(DeploymentArtifacts memory artifacts) internal view returns (string memory) {
        return string.concat(
            '{"treasuryPolicyEngine":"',
            vm.toString(artifacts.treasuryPolicyEngine),
            '","treasuryAccountFactory":"',
            vm.toString(artifacts.treasuryAccountFactory),
            '","allocationRouter":"',
            vm.toString(artifacts.allocationRouter),
            '","musdSavingsRateHandler":"',
            vm.toString(artifacts.musdSavingsRateHandler),
            '","tigrisStablePoolHandler":"',
            vm.toString(artifacts.tigrisStablePoolHandler),
            '","externalMusdSavingsRateMock":"',
            vm.toString(artifacts.externalMusdSavingsRateMock),
            '","treasuryAccount":"',
            vm.toString(artifacts.treasuryAccount),
            '"}'
        );
    }

    function _buildReferencesJson(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            '{"musdToken":"',
            vm.toString(config.musdToken),
            '","borrowerOperations":"',
            vm.toString(config.borrowerOperations),
            '","savingsDestination":"',
            vm.toString(artifacts.savingsDestination),
            '","tigrisRouter":"',
            vm.toString(config.tigrisRouter),
            '","tigrisMusdMusdcPool":"',
            vm.toString(config.tigrisMusdMusdcPool),
            '","musdcToken":"',
            vm.toString(config.musdcToken),
            '"}'
        );
    }

    function _buildTreasuryScenarioJson(DeploymentConfig memory config) internal view returns (string memory) {
        return string.concat(
            '{"liquidityBuffer":"',
            vm.toString(config.liquidityBuffer),
            '","approvalThreshold":"',
            vm.toString(config.approvalThreshold),
            '","savingsCap":"',
            vm.toString(config.savingsCap),
            '","tigrisCap":"',
            vm.toString(config.tigrisCap),
            '","automationEnabled":',
            _jsonBool(config.automationEnabled),
            ',"startPaused":',
            _jsonBool(config.startPaused),
            "}"
        );
    }

    function _jsonBool(bool _value) internal pure returns (string memory) {
        return _value ? "true" : "false";
    }
}
