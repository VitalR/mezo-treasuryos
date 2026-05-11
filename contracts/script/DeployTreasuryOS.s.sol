// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AllocationRouter } from "../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../src/adapters/MUSDSavingsRateHandler.sol";
import { TigrisStablePoolHandler } from "../src/adapters/TigrisStablePoolHandler.sol";
import { BTCReservePolicy } from "../src/core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { TreasuryAutomationExecutor } from "../src/core/TreasuryAutomationExecutor.sol";
import { TreasuryAccountFactory } from "../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../src/core/TreasuryPolicyEngine.sol";
import { ExternalMUSDSavingsRateMock } from "../src/external/ExternalMUSDSavingsRateMock.sol";
import { ProtocolFeeManager } from "../src/fees/ProtocolFeeManager.sol";
import { ProtocolFeeVault } from "../src/fees/ProtocolFeeVault.sol";
import { IAllocationHandler } from "../src/interfaces/IAllocationHandler.sol";
import { IMUSDSavingsRate } from "../src/interfaces/IMUSDSavingsRate.sol";
import { ITigrisBasicRouter } from "../src/interfaces/ITigrisBasicRouter.sol";
import { ITreasuryPolicyEngine } from "../src/interfaces/ITreasuryPolicyEngine.sol";
import { TreasuryMultisig } from "../src/multisig/TreasuryMultisig.sol";

/// @title DeployTreasuryOS
/// @notice Deploys a TreasuryOS demo stack on Mezo testnet and writes a deployment manifest.
contract DeployTreasuryOS is Script {
    uint256 internal constant DEFAULT_LIQUIDITY_BUFFER = 500e18;
    uint256 internal constant DEFAULT_APPROVAL_THRESHOLD = 250e18;
    uint256 internal constant DEFAULT_WARNING_COLLATERAL_RATIO_BPS = 18_000;
    uint256 internal constant DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant DEFAULT_MIN_OPEN_COLLATERAL_RATIO_BPS = 18_000;
    uint256 internal constant DEFAULT_TARGET_COLLATERAL_RATIO_BPS = 20_000;
    uint256 internal constant DEFAULT_STRESS_DROP_BPS = 2500;
    uint256 internal constant DEFAULT_MIN_POST_STRESS_COLLATERAL_RATIO_BPS = 14_000;
    uint256 internal constant DEFAULT_MIN_IDLE_BTC_RESERVE = 0.25 ether;
    uint256 internal constant DEFAULT_MAX_AUTO_BUFFER_RESTORE = 500e18;
    uint256 internal constant DEFAULT_MAX_AUTO_DEBT_REPAY = 250e18;
    uint256 internal constant DEFAULT_MAX_AUTO_IDLE_BTC_TOP_UP = 0.25 ether;
    uint256 internal constant DEFAULT_SAVINGS_CAP = 10_000e18;
    uint256 internal constant DEFAULT_TIGRIS_CAP = 5000e18;
    uint256 internal constant DEFAULT_TIGRIS_DEADLINE_WINDOW = 15 minutes;
    uint256 internal constant DEFAULT_TIGRIS_MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant DEFAULT_TREASURY_MULTISIG_THRESHOLD = 2;
    uint64 internal constant DEFAULT_TREASURY_MULTISIG_SIG_DELAY = 0;
    uint64 internal constant DEFAULT_TREASURY_MULTISIG_MAX_PENDING = 7 days;
    uint256 internal constant MEZO_TESTNET_CHAIN_ID = 31_611;

    struct DeploymentConfig {
        uint256 chainId;
        uint256 deployerPrivateKey;
        uint256 treasuryOwnerPrivateKey;
        uint256 treasuryMultisigProposerPrivateKey;
        address deployer;
        address treasuryOwner;
        address treasuryApprover;
        address treasuryOperator;
        address automationOperator;
        address[] treasuryMultisigOwners;
        uint256 treasuryMultisigThreshold;
        uint64 treasuryMultisigSigDelay;
        uint64 treasuryMultisigMaxPending;
        bool deployTreasuryMultisig;
        bool executeOwnerControlledSetup;
        bool proposeTreasuryMultisigSetup;
        address musdToken;
        address borrowerOperations;
        address savingsRate;
        address externalSavingsRateMock;
        bool deployExternalSavingsMock;
        address tigrisRouter;
        address tigrisPoolFactory;
        address tigrisMusdMusdcPool;
        address musdcToken;
        bool tigrisMusdMusdcStable;
        uint256 tigrisDeadlineWindow;
        uint256 tigrisMaxSlippageBps;
        uint256 liquidityBuffer;
        uint256 approvalThreshold;
        uint256 warningCollateralRatioBps;
        uint256 criticalCollateralRatioBps;
        uint256 minOpenCollateralRatioBps;
        uint256 targetCollateralRatioBps;
        uint256 stressDropBps;
        uint256 minPostStressCollateralRatioBps;
        uint256 minIdleBTCReserve;
        bool automationEnabled;
        address automationExecutor;
        uint256 maxAutoBufferRestore;
        uint256 maxAutoDebtRepay;
        uint256 maxAutoIdleBTCTopUp;
        bool allowAutoSavingsWithdraw;
        bool allowAutoDebtRepay;
        bool allowAutomationBTCTopUp;
        bool startPaused;
        uint256 savingsCap;
        uint256 tigrisCap;
        string manifestPath;
    }

    struct DeploymentArtifacts {
        address protocolFeeVault;
        address protocolFeeManager;
        address treasuryPolicyEngine;
        address btcReservePolicy;
        address treasuryAccountFactory;
        address treasuryAutomationExecutor;
        address treasuryMultisig;
        address allocationRouter;
        address musdSavingsRateHandler;
        address tigrisStablePoolHandler;
        address externalMusdSavingsRateMock;
        address treasuryAccount;
        address savingsDestination;
        uint256 ownerSetupBatchId;
        bool ownerSetupBatchProposed;
    }

    error InvalidAddress(string key);
    error InvalidOwnerConfiguration(address treasuryOwner, address derivedOwner);
    error InvalidTreasuryMultisigProposer(address proposer);
    error MissingOwnerPrivateKey(address treasuryOwner);
    error MissingTreasuryMultisigOwner();
    error MissingTreasuryMultisigProposerPrivateKey();
    error ExternalSavingsMockDisabledOnMezoTestnet();
    error Uint64Overflow(string key, uint256 value);

    /// @notice Deploys the TreasuryOS demo stack and writes a deployment manifest.
    function run() external returns (DeploymentArtifacts memory artifacts) {
        DeploymentConfig memory config = _loadConfig();

        console2.log("Deploying TreasuryOS to chain ID:", block.chainid);
        console2.log("Deployer:", config.deployer);

        artifacts = _deployCore(config);
        if (config.deployTreasuryMultisig) {
            config.treasuryOwner = artifacts.treasuryMultisig;
        }

        console2.log("Treasury owner:", config.treasuryOwner);

        _configureOwnerControlledState(config, artifacts);
        _writeManifest(config, artifacts);

        console2.log("ProtocolFeeVault:", artifacts.protocolFeeVault);
        console2.log("ProtocolFeeManager:", artifacts.protocolFeeManager);
        console2.log("TreasuryPolicyEngine:", artifacts.treasuryPolicyEngine);
        console2.log("BTCReservePolicy:", artifacts.btcReservePolicy);
        console2.log("TreasuryAccountFactory:", artifacts.treasuryAccountFactory);
        console2.log("TreasuryAutomationExecutor:", artifacts.treasuryAutomationExecutor);
        console2.log("TreasuryMultisig:", artifacts.treasuryMultisig);
        console2.log("AllocationRouter:", artifacts.allocationRouter);
        console2.log("TreasuryAccount:", artifacts.treasuryAccount);
        if (artifacts.ownerSetupBatchProposed) {
            console2.log("Owner setup batch ID:", artifacts.ownerSetupBatchId);
        }
        console2.log("Manifest:", config.manifestPath);
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.chainId = vm.envOr("MEZO_CHAIN_ID", block.chainid);
        config.deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        config.deployer = vm.addr(config.deployerPrivateKey);
        config.deployTreasuryMultisig = vm.envOr("DEPLOY_TREASURY_MULTISIG", false);
        config.treasuryOwner = vm.envOr("TREASURY_OWNER", address(0));
        config.treasuryApprover = vm.envAddress("TREASURY_APPROVER");
        config.treasuryOperator = vm.envAddress("TREASURY_OPERATOR");
        config.automationOperator = vm.envOr("DEMO_TREASURY_AUTOMATION_OPERATOR", address(0));
        if (config.deployTreasuryMultisig) {
            config.treasuryMultisigOwners = _loadTreasuryMultisigOwners();
            config.treasuryMultisigThreshold =
                vm.envOr("TREASURY_MULTISIG_THRESHOLD", DEFAULT_TREASURY_MULTISIG_THRESHOLD);
            config.treasuryMultisigSigDelay =
                _envUint64("TREASURY_MULTISIG_SIG_DELAY", DEFAULT_TREASURY_MULTISIG_SIG_DELAY);
            config.treasuryMultisigMaxPending =
                _envUint64("TREASURY_MULTISIG_MAX_PENDING", DEFAULT_TREASURY_MULTISIG_MAX_PENDING);
            config.proposeTreasuryMultisigSetup = vm.envOr("PROPOSE_TREASURY_MULTISIG_SETUP", true);
            config.treasuryMultisigProposerPrivateKey =
                vm.envOr("TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY", config.deployerPrivateKey);
        }
        config.executeOwnerControlledSetup = vm.envOr("EXECUTE_OWNER_CONTROLLED_SETUP", !config.deployTreasuryMultisig);
        config.musdToken = vm.envAddress("MEZO_MUSD_TOKEN");
        config.borrowerOperations = vm.envAddress("MEZO_BORROWER_OPERATIONS");
        config.savingsRate = vm.envOr("MEZO_MUSD_SAVINGS_RATE", address(0));
        config.externalSavingsRateMock = vm.envOr("EXTERNAL_MUSD_SAVINGS_RATE_MOCK", address(0));
        config.deployExternalSavingsMock = vm.envOr("DEPLOY_EXTERNAL_SAVINGS_MOCK", false);
        if (config.deployExternalSavingsMock && block.chainid == MEZO_TESTNET_CHAIN_ID) {
            revert ExternalSavingsMockDisabledOnMezoTestnet();
        }
        config.tigrisRouter = vm.envOr("MEZO_TIGRIS_ROUTER", address(0));
        config.tigrisPoolFactory = vm.envOr("MEZO_TIGRIS_POOL_FACTORY", address(0));
        config.tigrisMusdMusdcPool = vm.envOr("MEZO_TIGRIS_MUSD_MUSDC_POOL", address(0));
        config.musdcToken = vm.envOr("MEZO_MUSDC_TOKEN", address(0));
        config.tigrisMusdMusdcStable = vm.envOr("MEZO_TIGRIS_MUSD_MUSDC_STABLE", true);
        config.tigrisDeadlineWindow = vm.envOr("TIGRIS_DEADLINE_WINDOW", DEFAULT_TIGRIS_DEADLINE_WINDOW);
        config.tigrisMaxSlippageBps = vm.envOr("TIGRIS_MAX_SLIPPAGE_BPS", DEFAULT_TIGRIS_MAX_SLIPPAGE_BPS);
        config.liquidityBuffer = vm.envOr("DEMO_TREASURY_LIQUIDITY_BUFFER", DEFAULT_LIQUIDITY_BUFFER);
        config.approvalThreshold = vm.envOr("DEMO_TREASURY_APPROVAL_THRESHOLD", DEFAULT_APPROVAL_THRESHOLD);
        config.warningCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_WARNING_COLLATERAL_RATIO_BPS", DEFAULT_WARNING_COLLATERAL_RATIO_BPS);
        config.criticalCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_CRITICAL_COLLATERAL_RATIO_BPS", DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS);
        config.minOpenCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_MIN_OPEN_COLLATERAL_RATIO_BPS", DEFAULT_MIN_OPEN_COLLATERAL_RATIO_BPS);
        config.targetCollateralRatioBps =
            vm.envOr("DEMO_TREASURY_TARGET_COLLATERAL_RATIO_BPS", DEFAULT_TARGET_COLLATERAL_RATIO_BPS);
        config.stressDropBps = vm.envOr("DEMO_TREASURY_STRESS_DROP_BPS", DEFAULT_STRESS_DROP_BPS);
        config.minPostStressCollateralRatioBps = vm.envOr(
            "DEMO_TREASURY_MIN_POST_STRESS_COLLATERAL_RATIO_BPS", DEFAULT_MIN_POST_STRESS_COLLATERAL_RATIO_BPS
        );
        config.minIdleBTCReserve = vm.envOr("DEMO_TREASURY_MIN_IDLE_BTC_RESERVE", DEFAULT_MIN_IDLE_BTC_RESERVE);
        config.automationEnabled = vm.envOr("DEMO_TREASURY_AUTOMATION_ENABLED", true);
        config.automationExecutor = vm.envOr("DEMO_TREASURY_AUTOMATION_EXECUTOR", address(0));
        config.maxAutoBufferRestore = vm.envOr("DEMO_TREASURY_MAX_AUTO_BUFFER_RESTORE", DEFAULT_MAX_AUTO_BUFFER_RESTORE);
        config.maxAutoDebtRepay = vm.envOr("DEMO_TREASURY_MAX_AUTO_DEBT_REPAY", DEFAULT_MAX_AUTO_DEBT_REPAY);
        config.maxAutoIdleBTCTopUp =
            vm.envOr("DEMO_TREASURY_MAX_AUTO_IDLE_BTC_TOP_UP", DEFAULT_MAX_AUTO_IDLE_BTC_TOP_UP);
        config.allowAutoSavingsWithdraw = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_SAVINGS_WITHDRAW", true);
        config.allowAutoDebtRepay = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_DEBT_REPAY", true);
        config.allowAutomationBTCTopUp = vm.envOr("DEMO_TREASURY_ALLOW_AUTOMATION_BTC_TOP_UP", true);
        config.startPaused = vm.envOr("DEMO_TREASURY_START_PAUSED", false);
        config.savingsCap = vm.envOr("DEMO_SAVINGS_CAP", DEFAULT_SAVINGS_CAP);
        config.tigrisCap = vm.envOr("DEMO_TIGRIS_CAP", DEFAULT_TIGRIS_CAP);
        config.manifestPath = vm.envOr("DEPLOYMENT_MANIFEST_PATH", string("../deployments/mezo-testnet-demo.json"));

        if (config.deployTreasuryMultisig) {
            if (config.proposeTreasuryMultisigSetup) {
                if (config.treasuryMultisigProposerPrivateKey == 0) {
                    revert MissingTreasuryMultisigProposerPrivateKey();
                }

                address proposer = vm.addr(config.treasuryMultisigProposerPrivateKey);
                if (!_isTreasuryMultisigOwner(proposer, config.treasuryMultisigOwners)) {
                    revert InvalidTreasuryMultisigProposer(proposer);
                }
            }
        } else {
            config.treasuryOwnerPrivateKey = vm.envOr("TREASURY_OWNER_PRIVATE_KEY", uint256(0));
            if (config.executeOwnerControlledSetup && config.treasuryOwnerPrivateKey == 0) {
                if (config.treasuryOwner == config.deployer) {
                    config.treasuryOwnerPrivateKey = config.deployerPrivateKey;
                } else {
                    revert MissingOwnerPrivateKey(config.treasuryOwner);
                }
            }

            if (config.treasuryOwnerPrivateKey != 0) {
                address derivedOwner = vm.addr(config.treasuryOwnerPrivateKey);
                if (derivedOwner != config.treasuryOwner) {
                    revert InvalidOwnerConfiguration(config.treasuryOwner, derivedOwner);
                }
            }
        }

        if (!config.deployTreasuryMultisig && config.treasuryOwner == address(0)) {
            revert InvalidAddress("TREASURY_OWNER");
        }
        if (config.treasuryApprover == address(0)) revert InvalidAddress("TREASURY_APPROVER");
        if (config.treasuryOperator == address(0)) revert InvalidAddress("TREASURY_OPERATOR");
        if (config.musdToken == address(0)) revert InvalidAddress("MEZO_MUSD_TOKEN");
        if (config.borrowerOperations == address(0)) revert InvalidAddress("MEZO_BORROWER_OPERATIONS");
    }

    function _loadTreasuryMultisigOwners() internal view returns (address[] memory owners) {
        address[5] memory candidates = [
            vm.envOr("TREASURY_MULTISIG_OWNER_1", address(0)),
            vm.envOr("TREASURY_MULTISIG_OWNER_2", address(0)),
            vm.envOr("TREASURY_MULTISIG_OWNER_3", address(0)),
            vm.envOr("TREASURY_MULTISIG_OWNER_4", address(0)),
            vm.envOr("TREASURY_MULTISIG_OWNER_5", address(0))
        ];

        uint256 count;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] != address(0)) count++;
        }

        if (count == 0) revert MissingTreasuryMultisigOwner();

        owners = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] != address(0)) {
                owners[index++] = candidates[i];
            }
        }
    }

    function _envUint64(string memory _key, uint64 _defaultValue) internal view returns (uint64 value) {
        uint256 rawValue = vm.envOr(_key, uint256(_defaultValue));
        if (rawValue > type(uint64).max) revert Uint64Overflow(_key, rawValue);

        // forge-lint: disable-next-line(unsafe-typecast)
        value = uint64(rawValue);
    }

    function _isTreasuryMultisigOwner(address _owner, address[] memory _owners) internal pure returns (bool) {
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == _owner) {
                return true;
            }
        }

        return false;
    }

    function _deployCore(DeploymentConfig memory config) internal returns (DeploymentArtifacts memory artifacts) {
        vm.startBroadcast(config.deployerPrivateKey);

        address treasuryOwner = config.treasuryOwner;
        if (config.deployTreasuryMultisig) {
            TreasuryMultisig treasuryMultisig = new TreasuryMultisig(
                config.treasuryMultisigOwners,
                config.treasuryMultisigThreshold,
                config.treasuryMultisigSigDelay,
                config.treasuryMultisigMaxPending
            );
            artifacts.treasuryMultisig = address(treasuryMultisig);
            treasuryOwner = address(treasuryMultisig);
        }

        ProtocolFeeVault protocolFeeVault = new ProtocolFeeVault(config.deployer);
        ProtocolFeeManager protocolFeeManager = new ProtocolFeeManager(config.deployer, address(protocolFeeVault));
        TreasuryPolicyEngine treasuryPolicyEngine = new TreasuryPolicyEngine();
        BTCReservePolicy btcReservePolicy = new BTCReservePolicy(treasuryPolicyEngine);
        TreasuryAccountFactory treasuryAccountFactory =
            new TreasuryAccountFactory(IERC20(config.musdToken), treasuryPolicyEngine);
        TreasuryAutomationExecutor treasuryAutomationExecutor = new TreasuryAutomationExecutor(treasuryOwner);
        AllocationRouter allocationRouter = new AllocationRouter(treasuryOwner);

        artifacts.protocolFeeVault = address(protocolFeeVault);
        artifacts.protocolFeeManager = address(protocolFeeManager);
        artifacts.treasuryPolicyEngine = address(treasuryPolicyEngine);
        artifacts.btcReservePolicy = address(btcReservePolicy);
        artifacts.treasuryAccountFactory = address(treasuryAccountFactory);
        artifacts.treasuryAutomationExecutor = address(treasuryAutomationExecutor);
        artifacts.allocationRouter = address(allocationRouter);

        if (config.savingsRate != address(0)) {
            artifacts.savingsDestination = config.savingsRate;
        } else if (config.deployExternalSavingsMock) {
            if (config.externalSavingsRateMock == address(0)) {
                ExternalMUSDSavingsRateMock externalSavingsRateMock =
                    new ExternalMUSDSavingsRateMock(treasuryOwner, IERC20(config.musdToken));
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

        artifacts.tigrisStablePoolHandler = _deployTigrisStablePoolHandler(config, artifacts.allocationRouter);

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

        treasuryAccountFactory.setTreasuryAdminApproval(treasuryOwner, true);
        artifacts.treasuryAccount = treasuryAccountFactory.deployTreasuryAccount(treasuryOwner, policyConfig);

        vm.stopBroadcast();
    }

    /// @notice Deploys the optional Tigris MUSD/mUSDC handler when all live testnet references are configured.
    /// @param config Demo deployment config.
    /// @param allocationRouter Treasury allocation router.
    /// @return Deployed Tigris handler address, or zero when not configured.
    function _deployTigrisStablePoolHandler(DeploymentConfig memory config, address allocationRouter)
        internal
        returns (address)
    {
        if (
            config.tigrisRouter == address(0) || config.tigrisPoolFactory == address(0)
                || config.tigrisMusdMusdcPool == address(0) || config.musdcToken == address(0)
        ) {
            console2.log(
                "Skipping TigrisStablePoolHandler deployment: missing router, pool factory, pool, or MEZO_MUSDC_TOKEN"
            );
            return address(0);
        }

        TigrisStablePoolHandler tigrisStablePoolHandler = new TigrisStablePoolHandler(
            allocationRouter,
            ITigrisBasicRouter(config.tigrisRouter),
            config.tigrisMusdMusdcPool,
            config.tigrisPoolFactory,
            config.tigrisMusdMusdcStable,
            IERC20(config.musdToken),
            IERC20(config.musdcToken),
            config.tigrisDeadlineWindow,
            config.tigrisMaxSlippageBps
        );

        return address(tigrisStablePoolHandler);
    }

    function _configureOwnerControlledState(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildOwnerSetupBatch(config, artifacts);

        if (config.deployTreasuryMultisig) {
            if (!config.proposeTreasuryMultisigSetup) {
                console2.log("Skipping multisig owner-controlled setup proposal");
                return;
            }

            vm.startBroadcast(config.treasuryMultisigProposerPrivateKey);
            artifacts.ownerSetupBatchId = TreasuryMultisig(payable(artifacts.treasuryMultisig))
                .proposeBatchTransaction(targets, values, payloads, keccak256("TREASURYOS_SETUP"));
            artifacts.ownerSetupBatchProposed = true;
            vm.stopBroadcast();

            return;
        }

        if (!config.executeOwnerControlledSetup) {
            console2.log("Skipping owner-controlled setup execution");
            return;
        }

        vm.startBroadcast(config.treasuryOwnerPrivateKey);

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returndata) = targets[i].call{ value: values[i] }(payloads[i]);
            _revertIfCallFailed(success, returndata);
        }

        vm.stopBroadcast();
    }

    function _buildOwnerSetupBatch(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        uint256 count = 6;
        if (artifacts.musdSavingsRateHandler != address(0) && artifacts.savingsDestination != address(0)) count++;
        if (artifacts.tigrisStablePoolHandler != address(0) && config.tigrisMusdMusdcPool != address(0)) count++;
        if (config.automationOperator != address(0)) count++;

        targets = new address[](count);
        values = new uint256[](count);
        payloads = new bytes[](count);

        uint256 index;

        if (artifacts.musdSavingsRateHandler != address(0) && artifacts.savingsDestination != address(0)) {
            targets[index] = artifacts.allocationRouter;
            payloads[index++] = abi.encodeCall(
                AllocationRouter.setHandler,
                (artifacts.savingsDestination, IAllocationHandler(artifacts.musdSavingsRateHandler))
            );
        }

        if (artifacts.tigrisStablePoolHandler != address(0) && config.tigrisMusdMusdcPool != address(0)) {
            targets[index] = artifacts.allocationRouter;
            payloads[index++] = abi.encodeCall(
                AllocationRouter.setHandler,
                (config.tigrisMusdMusdcPool, IAllocationHandler(artifacts.tigrisStablePoolHandler))
            );
        }

        targets[index] = artifacts.treasuryAccount;
        payloads[index++] = abi.encodeCall(TreasuryAccount.setBorrowerOperations, (config.borrowerOperations));

        targets[index] = artifacts.treasuryAccount;
        payloads[index++] = abi.encodeCall(TreasuryAccount.setAllocationRouter, (artifacts.allocationRouter));

        targets[index] = artifacts.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationLimits,
            (artifacts.treasuryAccount, config.maxAutoBufferRestore, config.maxAutoDebtRepay)
        );

        targets[index] = artifacts.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationCapabilities,
            (artifacts.treasuryAccount, config.allowAutoSavingsWithdraw, config.allowAutoDebtRepay)
        );

        targets[index] = artifacts.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateRiskControls, (artifacts.treasuryAccount, _riskControlConfig(config))
        );

        address automationExecutor = _effectiveAutomationExecutor(config, artifacts);
        targets[index] = artifacts.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationExecutor, (artifacts.treasuryAccount, automationExecutor)
        );

        if (config.automationOperator != address(0)) {
            targets[index] = automationExecutor;
            payloads[index] =
                abi.encodeCall(TreasuryAutomationExecutor.setAutomationOperator, (config.automationOperator, true));
        }
    }

    function _riskControlConfig(DeploymentConfig memory config)
        internal
        pure
        returns (ITreasuryPolicyEngine.RiskControlConfig memory riskConfig)
    {
        riskConfig = ITreasuryPolicyEngine.RiskControlConfig({
            minOpenCollateralRatioBps: config.minOpenCollateralRatioBps,
            targetCollateralRatioBps: config.targetCollateralRatioBps,
            stressDropBps: config.stressDropBps,
            minPostStressCollateralRatioBps: config.minPostStressCollateralRatioBps,
            minIdleBTCReserve: config.minIdleBTCReserve,
            maxAutoIdleBTCTopUp: config.maxAutoIdleBTCTopUp,
            allowAutomationBTCTopUp: config.allowAutomationBTCTopUp
        });
    }

    function _effectiveAutomationExecutor(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
        pure
        returns (address)
    {
        if (config.automationExecutor != address(0)) {
            return config.automationExecutor;
        }

        return artifacts.treasuryAutomationExecutor;
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
        string memory ownerSetupJson = _buildOwnerSetupJson(config, artifacts);

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
            ",",
            '"ownerSetup":',
            ownerSetupJson,
            "}"
        );

        vm.writeJson(json, config.manifestPath);
    }

    function _buildActorsJson(DeploymentConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"deployer":"',
            vm.toString(config.deployer),
            '","treasuryOwner":"',
            vm.toString(config.treasuryOwner),
            '","treasuryControlMode":"',
            config.deployTreasuryMultisig ? "treasuryMultisig" : "externalOrEoa",
            '","treasuryApprover":"',
            vm.toString(config.treasuryApprover),
            '","treasuryOperator":"',
            vm.toString(config.treasuryOperator),
            '","automationOperator":"',
            vm.toString(config.automationOperator),
            '","treasuryMultisigOwners":',
            _buildAddressArrayJson(config.treasuryMultisigOwners),
            "}"
        );
    }

    function _buildContractsJson(DeploymentArtifacts memory artifacts) internal pure returns (string memory) {
        return string.concat(
            '{"treasuryPolicyEngine":"',
            vm.toString(artifacts.treasuryPolicyEngine),
            '","protocolFeeVault":"',
            vm.toString(artifacts.protocolFeeVault),
            '","protocolFeeManager":"',
            vm.toString(artifacts.protocolFeeManager),
            '","btcReservePolicy":"',
            vm.toString(artifacts.btcReservePolicy),
            '","treasuryAccountFactory":"',
            vm.toString(artifacts.treasuryAccountFactory),
            '","treasuryAutomationExecutor":"',
            vm.toString(artifacts.treasuryAutomationExecutor),
            '","treasuryMultisig":"',
            vm.toString(artifacts.treasuryMultisig),
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
        address tigrisMcbtcBtcPool = vm.envOr("MEZO_TIGRIS_MCBTC_BTC_POOL", address(0));

        return string.concat(
            '{"musdToken":"',
            vm.toString(config.musdToken),
            '","borrowerOperations":"',
            vm.toString(config.borrowerOperations),
            '","savingsDestination":"',
            vm.toString(artifacts.savingsDestination),
            '","tigrisRouter":"',
            vm.toString(config.tigrisRouter),
            '","tigrisPoolFactory":"',
            vm.toString(config.tigrisPoolFactory),
            '","tigrisMusdMusdcPool":"',
            vm.toString(config.tigrisMusdMusdcPool),
            '","tigrisMcbtcBtcPool":"',
            vm.toString(tigrisMcbtcBtcPool),
            '","musdcToken":"',
            vm.toString(config.musdcToken),
            '","tigrisMusdMusdcStable":',
            _jsonBool(config.tigrisMusdMusdcStable),
            ',"tigrisDeadlineWindow":"',
            vm.toString(config.tigrisDeadlineWindow),
            '","tigrisMaxSlippageBps":"',
            vm.toString(config.tigrisMaxSlippageBps),
            '"}'
        );
    }

    function _buildTreasuryScenarioJson(DeploymentConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"liquidityBuffer":"',
            vm.toString(config.liquidityBuffer),
            '","approvalThreshold":"',
            vm.toString(config.approvalThreshold),
            '","savingsCap":"',
            vm.toString(config.savingsCap),
            '","tigrisCap":"',
            vm.toString(config.tigrisCap),
            '","tigrisMaxSlippageBps":"',
            vm.toString(config.tigrisMaxSlippageBps),
            '","riskControls":',
            _buildRiskControlsJson(config),
            ',"automationEnabled":',
            _jsonBool(config.automationEnabled),
            ',"startPaused":',
            _jsonBool(config.startPaused),
            "}"
        );
    }

    function _buildRiskControlsJson(DeploymentConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"minOpenCollateralRatioBps":"',
            vm.toString(config.minOpenCollateralRatioBps),
            '","targetCollateralRatioBps":"',
            vm.toString(config.targetCollateralRatioBps),
            '","stressDropBps":"',
            vm.toString(config.stressDropBps),
            '","minPostStressCollateralRatioBps":"',
            vm.toString(config.minPostStressCollateralRatioBps),
            '","minIdleBTCReserve":"',
            vm.toString(config.minIdleBTCReserve),
            '","maxAutoIdleBTCTopUp":"',
            vm.toString(config.maxAutoIdleBTCTopUp),
            '","allowAutomationBTCTopUp":',
            _jsonBool(config.allowAutomationBTCTopUp),
            "}"
        );
    }

    function _buildOwnerSetupJson(DeploymentConfig memory config, DeploymentArtifacts memory artifacts)
        internal
        pure
        returns (string memory)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildOwnerSetupBatch(config, artifacts);

        return string.concat(
            '{"executeOwnerControlledSetup":',
            _jsonBool(config.executeOwnerControlledSetup),
            ',"proposeTreasuryMultisigSetup":',
            _jsonBool(config.proposeTreasuryMultisigSetup),
            ',"ownerSetupBatchProposed":',
            _jsonBool(artifacts.ownerSetupBatchProposed),
            ',"ownerSetupBatchId":"',
            vm.toString(artifacts.ownerSetupBatchId),
            '","treasuryMultisigThreshold":"',
            vm.toString(config.treasuryMultisigThreshold),
            '","treasuryMultisigSigDelay":"',
            vm.toString(config.treasuryMultisigSigDelay),
            '","treasuryMultisigMaxPending":"',
            vm.toString(config.treasuryMultisigMaxPending),
            '","calls":',
            _buildOwnerSetupCallsJson(targets, values, payloads),
            "}"
        );
    }

    function _buildOwnerSetupCallsJson(address[] memory _targets, uint256[] memory _values, bytes[] memory _payloads)
        internal
        pure
        returns (string memory json)
    {
        json = "[";

        for (uint256 i = 0; i < _targets.length; i++) {
            if (i > 0) {
                json = string.concat(json, ",");
            }

            json = string.concat(
                json,
                '{"target":"',
                vm.toString(_targets[i]),
                '","value":"',
                vm.toString(_values[i]),
                '","data":"',
                vm.toString(_payloads[i]),
                '"}'
            );
        }

        json = string.concat(json, "]");
    }

    function _buildAddressArrayJson(address[] memory _addresses) internal pure returns (string memory json) {
        json = "[";

        for (uint256 i = 0; i < _addresses.length; i++) {
            if (i > 0) {
                json = string.concat(json, ",");
            }

            json = string.concat(json, '"', vm.toString(_addresses[i]), '"');
        }

        json = string.concat(json, "]");
    }

    function _revertIfCallFailed(bool _success, bytes memory _returndata) internal pure {
        if (_success) {
            return;
        }

        if (_returndata.length == 0) {
            revert("OWNER_SETUP_CALL_FAILED");
        }

        assembly {
            revert(add(_returndata, 32), mload(_returndata))
        }
    }

    function _jsonBool(bool _value) internal pure returns (string memory) {
        return _value ? "true" : "false";
    }
}
