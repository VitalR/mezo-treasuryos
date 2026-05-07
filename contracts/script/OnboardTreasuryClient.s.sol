// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AllocationRouter } from "../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../src/adapters/MUSDSavingsRateHandler.sol";
import { TigrisStablePoolHandler } from "../src/adapters/TigrisStablePoolHandler.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../src/core/TreasuryAccountFactory.sol";
import { TreasuryAutomationExecutor } from "../src/core/TreasuryAutomationExecutor.sol";
import { TreasuryPolicyEngine } from "../src/core/TreasuryPolicyEngine.sol";
import { ExternalMUSDSavingsRateMock } from "../src/external/ExternalMUSDSavingsRateMock.sol";
import { IAllocationHandler } from "../src/interfaces/IAllocationHandler.sol";
import { IMUSDSavingsRate } from "../src/interfaces/IMUSDSavingsRate.sol";
import { ITigrisBasicRouter } from "../src/interfaces/ITigrisBasicRouter.sol";
import { ITreasuryPolicyEngine } from "../src/interfaces/ITreasuryPolicyEngine.sol";
import { TreasuryMultisig } from "../src/multisig/TreasuryMultisig.sol";

/// @title OnboardTreasuryClient
/// @notice Deploys one client-owned TreasuryOS account stack against an existing protocol core deployment.
/// @dev The protocol admin/deployer only runs onboarding rails. The resulting Treasury Account, allocation router,
///      automation executor, and optional TreasuryMultisig are owned by the client treasury admin.
contract OnboardTreasuryClient is Script {
    // =============================================================
    // Constants
    // =============================================================

    uint256 internal constant DEFAULT_LIQUIDITY_BUFFER = 500e18;
    uint256 internal constant DEFAULT_APPROVAL_THRESHOLD = 250e18;
    uint256 internal constant DEFAULT_WARNING_COLLATERAL_RATIO_BPS = 18_000;
    uint256 internal constant DEFAULT_CRITICAL_COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant DEFAULT_MAX_AUTO_BUFFER_RESTORE = 500e18;
    uint256 internal constant DEFAULT_MAX_AUTO_DEBT_REPAY = 250e18;
    uint256 internal constant DEFAULT_SAVINGS_CAP = 10_000e18;
    uint256 internal constant DEFAULT_TIGRIS_CAP = 5000e18;
    uint256 internal constant DEFAULT_TIGRIS_DEADLINE_WINDOW = 15 minutes;
    uint256 internal constant DEFAULT_TIGRIS_MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant DEFAULT_CLIENT_TREASURY_MULTISIG_THRESHOLD = 1;
    uint64 internal constant DEFAULT_CLIENT_TREASURY_MULTISIG_SIG_DELAY = 0;
    uint64 internal constant DEFAULT_CLIENT_TREASURY_MULTISIG_MAX_PENDING = 7 days;

    // =============================================================
    // Types
    // =============================================================

    /// @notice Client onboarding configuration loaded from the environment.
    struct ClientConfig {
        uint256 chainId;
        uint256 deployerPrivateKey;
        uint256 clientMultisigProposerPrivateKey;
        address protocolAdmin;
        address treasuryPolicyEngine;
        address treasuryAccountFactory;
        address clientTreasuryOwner;
        address treasuryApprover;
        address treasuryOperator;
        address automationOperator;
        address[] clientMultisigOwners;
        uint256 clientMultisigThreshold;
        uint64 clientMultisigSigDelay;
        uint64 clientMultisigMaxPending;
        bool deployClientMultisig;
        bool executeClientOwnerSetup;
        bool proposeClientMultisigSetup;
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

    /// @notice Client onboarding artifacts written to the deployment manifest.
    struct ClientArtifacts {
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

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when a required environment address is zero.
    /// @param key Missing or invalid environment key.
    error InvalidAddress(string key);
    /// @notice Raised when a configured owner private key does not derive to the configured owner address.
    /// @param configuredOwner Owner address configured in the environment.
    /// @param derivedOwner Address derived from the private key.
    error InvalidOwnerConfiguration(address configuredOwner, address derivedOwner);
    /// @notice Raised when a multisig setup proposer is not one of the configured multisig owners.
    /// @param proposer Address derived from the proposer private key.
    error InvalidClientMultisigProposer(address proposer);
    /// @notice Raised when direct EOA setup is enabled but the client owner private key is missing.
    /// @param clientTreasuryOwner Client treasury owner that must execute setup.
    error MissingClientOwnerPrivateKey(address clientTreasuryOwner);
    /// @notice Raised when no initial client multisig signer is configured.
    error MissingClientMultisigOwner();
    /// @notice Raised when multisig setup proposal is enabled but no proposer private key is configured.
    error MissingClientMultisigProposerPrivateKey();
    /// @notice Raised when an environment integer does not fit into uint64.
    /// @param key Environment key.
    /// @param value Oversized value.
    error Uint64Overflow(string key, uint256 value);

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Onboards one client treasury instance against an already deployed TreasuryOS protocol core.
    /// @return artifacts Client onboarding artifacts.
    function run() external returns (ClientArtifacts memory artifacts) {
        ClientConfig memory config = _loadConfig();

        console2.log("Onboarding TreasuryOS client to chain ID:", block.chainid);
        console2.log("Protocol admin:", config.protocolAdmin);

        artifacts = _deployClientStack(config);
        if (config.deployClientMultisig) {
            config.clientTreasuryOwner = artifacts.treasuryMultisig;
        }

        console2.log("Client treasury owner:", config.clientTreasuryOwner);

        _configureClientOwnerControlledState(config, artifacts);
        _writeManifest(config, artifacts);

        console2.log("TreasuryMultisig:", artifacts.treasuryMultisig);
        console2.log("TreasuryAutomationExecutor:", artifacts.treasuryAutomationExecutor);
        console2.log("AllocationRouter:", artifacts.allocationRouter);
        console2.log("TreasuryAccount:", artifacts.treasuryAccount);
        if (artifacts.ownerSetupBatchProposed) {
            console2.log("Client owner setup batch ID:", artifacts.ownerSetupBatchId);
        }
        console2.log("Manifest:", config.manifestPath);
    }

    // =============================================================
    // Config
    // =============================================================

    /// @notice Loads client onboarding configuration from environment variables.
    /// @return config Client onboarding config.
    function _loadConfig() internal view returns (ClientConfig memory config) {
        config.chainId = vm.envOr("MEZO_CHAIN_ID", block.chainid);
        config.deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        config.protocolAdmin = vm.addr(config.deployerPrivateKey);
        config.treasuryPolicyEngine = vm.envAddress("TREASURY_POLICY_ENGINE");
        config.treasuryAccountFactory = vm.envAddress("TREASURY_ACCOUNT_FACTORY");
        config.deployClientMultisig =
            vm.envOr("DEPLOY_CLIENT_TREASURY_MULTISIG", vm.envOr("DEPLOY_TREASURY_MULTISIG", true));
        config.clientTreasuryOwner = _envAddressWithFallback("CLIENT_TREASURY_OWNER", "TREASURY_OWNER", address(0));
        config.treasuryApprover = vm.envAddress("TREASURY_APPROVER");
        config.treasuryOperator = vm.envAddress("TREASURY_OPERATOR");
        config.automationOperator = vm.envOr("DEMO_TREASURY_AUTOMATION_OPERATOR", address(0));

        if (config.deployClientMultisig) {
            config.clientMultisigOwners = _loadClientMultisigOwners();
            config.clientMultisigThreshold = vm.envOr(
                "CLIENT_TREASURY_MULTISIG_THRESHOLD",
                vm.envOr("TREASURY_MULTISIG_THRESHOLD", DEFAULT_CLIENT_TREASURY_MULTISIG_THRESHOLD)
            );
            config.clientMultisigSigDelay = _envUint64WithFallback(
                "CLIENT_TREASURY_MULTISIG_SIG_DELAY",
                "TREASURY_MULTISIG_SIG_DELAY",
                DEFAULT_CLIENT_TREASURY_MULTISIG_SIG_DELAY
            );
            config.clientMultisigMaxPending = _envUint64WithFallback(
                "CLIENT_TREASURY_MULTISIG_MAX_PENDING",
                "TREASURY_MULTISIG_MAX_PENDING",
                DEFAULT_CLIENT_TREASURY_MULTISIG_MAX_PENDING
            );
            config.proposeClientMultisigSetup =
                vm.envOr("PROPOSE_CLIENT_TREASURY_MULTISIG_SETUP", vm.envOr("PROPOSE_TREASURY_MULTISIG_SETUP", true));
            config.clientMultisigProposerPrivateKey = vm.envOr(
                "CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY",
                vm.envOr("TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY", uint256(0))
            );
        }

        config.executeClientOwnerSetup = vm.envOr(
            "EXECUTE_CLIENT_OWNER_SETUP", vm.envOr("EXECUTE_OWNER_CONTROLLED_SETUP", !config.deployClientMultisig)
        );
        config.musdToken = vm.envAddress("MEZO_MUSD_TOKEN");
        config.borrowerOperations = vm.envAddress("MEZO_BORROWER_OPERATIONS");
        config.savingsRate = vm.envOr("MEZO_MUSD_SAVINGS_RATE", address(0));
        config.externalSavingsRateMock = vm.envOr("EXTERNAL_MUSD_SAVINGS_RATE_MOCK", address(0));
        config.deployExternalSavingsMock = vm.envOr("DEPLOY_EXTERNAL_SAVINGS_MOCK", config.savingsRate == address(0));
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
        config.automationEnabled = vm.envOr("DEMO_TREASURY_AUTOMATION_ENABLED", true);
        config.automationExecutor = vm.envOr("DEMO_TREASURY_AUTOMATION_EXECUTOR", address(0));
        config.maxAutoBufferRestore = vm.envOr("DEMO_TREASURY_MAX_AUTO_BUFFER_RESTORE", DEFAULT_MAX_AUTO_BUFFER_RESTORE);
        config.maxAutoDebtRepay = vm.envOr("DEMO_TREASURY_MAX_AUTO_DEBT_REPAY", DEFAULT_MAX_AUTO_DEBT_REPAY);
        config.allowAutoSavingsWithdraw = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_SAVINGS_WITHDRAW", true);
        config.allowAutoDebtRepay = vm.envOr("DEMO_TREASURY_ALLOW_AUTO_DEBT_REPAY", true);
        config.startPaused = vm.envOr("DEMO_TREASURY_START_PAUSED", false);
        config.savingsCap = vm.envOr("DEMO_SAVINGS_CAP", DEFAULT_SAVINGS_CAP);
        config.tigrisCap = vm.envOr("DEMO_TIGRIS_CAP", DEFAULT_TIGRIS_CAP);
        config.manifestPath =
            vm.envOr("CLIENT_DEPLOYMENT_MANIFEST_PATH", string("../deployments/mezo-testnet-client.json"));

        _validateConfig(config);
    }

    /// @notice Validates client onboarding configuration.
    /// @param config Client onboarding config.
    function _validateConfig(ClientConfig memory config) internal view {
        if (config.treasuryPolicyEngine == address(0)) revert InvalidAddress("TREASURY_POLICY_ENGINE");
        if (config.treasuryAccountFactory == address(0)) revert InvalidAddress("TREASURY_ACCOUNT_FACTORY");
        if (config.treasuryApprover == address(0)) revert InvalidAddress("TREASURY_APPROVER");
        if (config.treasuryOperator == address(0)) revert InvalidAddress("TREASURY_OPERATOR");
        if (config.musdToken == address(0)) revert InvalidAddress("MEZO_MUSD_TOKEN");
        if (config.borrowerOperations == address(0)) revert InvalidAddress("MEZO_BORROWER_OPERATIONS");

        if (config.deployClientMultisig) {
            if (config.proposeClientMultisigSetup) {
                if (config.clientMultisigProposerPrivateKey == 0) {
                    revert MissingClientMultisigProposerPrivateKey();
                }

                address proposer = vm.addr(config.clientMultisigProposerPrivateKey);
                if (!_isAddressInArray(proposer, config.clientMultisigOwners)) {
                    revert InvalidClientMultisigProposer(proposer);
                }
            }

            return;
        }

        if (config.clientTreasuryOwner == address(0)) revert InvalidAddress("CLIENT_TREASURY_OWNER");

        uint256 clientOwnerPrivateKey =
            vm.envOr("CLIENT_TREASURY_OWNER_PRIVATE_KEY", vm.envOr("TREASURY_OWNER_PRIVATE_KEY", uint256(0)));
        if (config.executeClientOwnerSetup && clientOwnerPrivateKey == 0) {
            if (config.clientTreasuryOwner != config.protocolAdmin) {
                revert MissingClientOwnerPrivateKey(config.clientTreasuryOwner);
            }
        }

        if (clientOwnerPrivateKey != 0) {
            address derivedOwner = vm.addr(clientOwnerPrivateKey);
            if (derivedOwner != config.clientTreasuryOwner) {
                revert InvalidOwnerConfiguration(config.clientTreasuryOwner, derivedOwner);
            }
        }
    }

    /// @notice Loads the configured client owner private key for direct EOA setup.
    /// @param config Client onboarding config.
    /// @return privateKey Client owner private key or protocol admin key if same address.
    function _clientOwnerPrivateKey(ClientConfig memory config) internal view returns (uint256 privateKey) {
        privateKey = vm.envOr("CLIENT_TREASURY_OWNER_PRIVATE_KEY", vm.envOr("TREASURY_OWNER_PRIVATE_KEY", uint256(0)));
        if (privateKey == 0 && config.clientTreasuryOwner == config.protocolAdmin) {
            privateKey = config.deployerPrivateKey;
        }
    }

    /// @notice Loads up to five initial client multisig owners from client-prefixed or legacy env keys.
    /// @return owners Initial signer set.
    function _loadClientMultisigOwners() internal view returns (address[] memory owners) {
        address[5] memory candidates = [
            _envAddressWithFallback("CLIENT_TREASURY_MULTISIG_OWNER_1", "TREASURY_MULTISIG_OWNER_1", address(0)),
            _envAddressWithFallback("CLIENT_TREASURY_MULTISIG_OWNER_2", "TREASURY_MULTISIG_OWNER_2", address(0)),
            _envAddressWithFallback("CLIENT_TREASURY_MULTISIG_OWNER_3", "TREASURY_MULTISIG_OWNER_3", address(0)),
            _envAddressWithFallback("CLIENT_TREASURY_MULTISIG_OWNER_4", "TREASURY_MULTISIG_OWNER_4", address(0)),
            _envAddressWithFallback("CLIENT_TREASURY_MULTISIG_OWNER_5", "TREASURY_MULTISIG_OWNER_5", address(0))
        ];

        uint256 count;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] != address(0)) count++;
        }

        if (count == 0) revert MissingClientMultisigOwner();

        owners = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] != address(0)) {
                owners[index++] = candidates[i];
            }
        }
    }

    // =============================================================
    // Deployment
    // =============================================================

    /// @notice Deploys client-owned support contracts and creates the official Treasury Account through the factory.
    /// @param config Client onboarding config.
    /// @return artifacts Client deployment artifacts.
    function _deployClientStack(ClientConfig memory config) internal returns (ClientArtifacts memory artifacts) {
        vm.startBroadcast(config.deployerPrivateKey);

        address clientTreasuryOwner = config.clientTreasuryOwner;
        if (config.deployClientMultisig) {
            TreasuryMultisig treasuryMultisig = new TreasuryMultisig(
                config.clientMultisigOwners,
                config.clientMultisigThreshold,
                config.clientMultisigSigDelay,
                config.clientMultisigMaxPending
            );
            artifacts.treasuryMultisig = address(treasuryMultisig);
            clientTreasuryOwner = address(treasuryMultisig);
        }

        TreasuryAutomationExecutor treasuryAutomationExecutor = new TreasuryAutomationExecutor(clientTreasuryOwner);
        AllocationRouter allocationRouter = new AllocationRouter(clientTreasuryOwner);

        artifacts.treasuryAutomationExecutor = address(treasuryAutomationExecutor);
        artifacts.allocationRouter = address(allocationRouter);

        if (config.savingsRate != address(0)) {
            artifacts.savingsDestination = config.savingsRate;
        } else if (config.deployExternalSavingsMock) {
            if (config.externalSavingsRateMock == address(0)) {
                ExternalMUSDSavingsRateMock externalSavingsRateMock =
                    new ExternalMUSDSavingsRateMock(clientTreasuryOwner, IERC20(config.musdToken));
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
            config.tigrisRouter != address(0) && config.tigrisPoolFactory != address(0)
                && config.tigrisMusdMusdcPool != address(0) && config.musdcToken != address(0)
        ) {
            TigrisStablePoolHandler tigrisStablePoolHandler = new TigrisStablePoolHandler(
                artifacts.allocationRouter,
                ITigrisBasicRouter(config.tigrisRouter),
                config.tigrisMusdMusdcPool,
                config.tigrisPoolFactory,
                config.tigrisMusdMusdcStable,
                IERC20(config.musdToken),
                IERC20(config.musdcToken),
                config.tigrisDeadlineWindow,
                config.tigrisMaxSlippageBps
            );

            artifacts.tigrisStablePoolHandler = address(tigrisStablePoolHandler);
        } else {
            console2.log(
                "Skipping TigrisStablePoolHandler deployment: missing router, pool factory, pool, or MEZO_MUSDC_TOKEN"
            );
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

        TreasuryAccountFactory treasuryAccountFactory = TreasuryAccountFactory(config.treasuryAccountFactory);
        treasuryAccountFactory.setTreasuryAdminApproval(clientTreasuryOwner, true);
        artifacts.treasuryAccount = treasuryAccountFactory.deployTreasuryAccount(clientTreasuryOwner, policyConfig);

        vm.stopBroadcast();
    }

    /// @notice Executes or proposes owner-controlled client setup calls.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    function _configureClientOwnerControlledState(ClientConfig memory config, ClientArtifacts memory artifacts)
        internal
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildClientOwnerSetupBatch(config, artifacts);

        if (config.deployClientMultisig) {
            if (!config.proposeClientMultisigSetup) {
                console2.log("Skipping client multisig setup proposal");
                return;
            }

            vm.startBroadcast(config.clientMultisigProposerPrivateKey);
            artifacts.ownerSetupBatchId = TreasuryMultisig(payable(artifacts.treasuryMultisig))
                .proposeBatchTransaction(targets, values, payloads, keccak256("TREASURYOS_CLIENT_SETUP"));
            artifacts.ownerSetupBatchProposed = true;
            vm.stopBroadcast();

            return;
        }

        if (!config.executeClientOwnerSetup) {
            console2.log("Skipping client owner-controlled setup execution");
            return;
        }

        vm.startBroadcast(_clientOwnerPrivateKey(config));

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returndata) = targets[i].call{ value: values[i] }(payloads[i]);
            _revertIfCallFailed(success, returndata);
        }

        vm.stopBroadcast();
    }

    /// @notice Builds setup calls that must be authorized by the client treasury owner.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    /// @return targets Setup targets.
    /// @return values Native values forwarded by each setup call.
    /// @return payloads Setup calldata payloads.
    function _buildClientOwnerSetupBatch(ClientConfig memory config, ClientArtifacts memory artifacts)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        uint256 count = 5;
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

        targets[index] = config.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationLimits,
            (artifacts.treasuryAccount, config.maxAutoBufferRestore, config.maxAutoDebtRepay)
        );

        targets[index] = config.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationCapabilities,
            (artifacts.treasuryAccount, config.allowAutoSavingsWithdraw, config.allowAutoDebtRepay)
        );

        address automationExecutor = _effectiveAutomationExecutor(config, artifacts);
        targets[index] = config.treasuryPolicyEngine;
        payloads[index++] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationExecutor, (artifacts.treasuryAccount, automationExecutor)
        );

        if (config.automationOperator != address(0)) {
            targets[index] = automationExecutor;
            payloads[index] =
                abi.encodeCall(TreasuryAutomationExecutor.setAutomationOperator, (config.automationOperator, true));
        }
    }

    /// @notice Returns the configured automation executor override or the deployed client executor.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    /// @return Automation executor used by the policy engine.
    function _effectiveAutomationExecutor(ClientConfig memory config, ClientArtifacts memory artifacts)
        internal
        pure
        returns (address)
    {
        if (config.automationExecutor != address(0)) {
            return config.automationExecutor;
        }

        return artifacts.treasuryAutomationExecutor;
    }

    // =============================================================
    // Destination Helpers
    // =============================================================

    /// @notice Builds the initial destination allowlist for the client policy.
    /// @param _savingsDestination Mezo savings destination, if configured.
    /// @param _tigrisStablePoolHandler Tigris handler address, if deployed.
    /// @param config Client onboarding config.
    /// @return destinations Initial approved destinations.
    function _buildApprovedDestinations(
        address _savingsDestination,
        address _tigrisStablePoolHandler,
        ClientConfig memory config
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

    /// @notice Builds initial per-destination allocation caps.
    /// @param _savingsDestination Mezo savings destination, if configured.
    /// @param _tigrisStablePoolHandler Tigris handler address, if deployed.
    /// @param config Client onboarding config.
    /// @return caps Initial destination caps.
    function _buildDestinationCaps(
        address _savingsDestination,
        address _tigrisStablePoolHandler,
        ClientConfig memory config
    ) internal pure returns (uint256[] memory caps) {
        uint256 count;
        if (_savingsDestination != address(0)) count++;
        if (_tigrisStablePoolHandler != address(0)) count++;

        caps = new uint256[](count);

        uint256 index;
        if (_savingsDestination != address(0)) {
            caps[index++] = config.savingsCap;
        }

        if (_tigrisStablePoolHandler != address(0)) {
            caps[index] = config.tigrisCap;
        }
    }

    // =============================================================
    // Manifest
    // =============================================================

    /// @notice Writes a client onboarding manifest for services, dashboard, and review artifacts.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    function _writeManifest(ClientConfig memory config, ClientArtifacts memory artifacts) internal {
        string memory json = string.concat(
            "{",
            '"manifestVersion":1,',
            '"scenario":"mezo-testnet-client",',
            '"network":{"name":"Mezo Testnet","chainId":',
            vm.toString(config.chainId),
            "},",
            '"chainIdObserved":',
            vm.toString(block.chainid),
            ",",
            '"actors":',
            _buildActorsJson(config),
            ",",
            '"protocolCore":',
            _buildProtocolCoreJson(config),
            ",",
            '"contracts":',
            _buildContractsJson(artifacts),
            ",",
            '"references":',
            _buildReferencesJson(config, artifacts),
            ",",
            '"treasuryScenario":',
            _buildTreasuryScenarioJson(config),
            ",",
            '"clientOwnerSetup":',
            _buildClientOwnerSetupJson(config, artifacts),
            "}"
        );

        vm.writeJson(json, config.manifestPath);
    }

    /// @notice Builds manifest actor JSON.
    /// @param config Client onboarding config.
    /// @return Actor JSON fragment.
    function _buildActorsJson(ClientConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"protocolAdmin":"',
            vm.toString(config.protocolAdmin),
            '","clientTreasuryOwner":"',
            vm.toString(config.clientTreasuryOwner),
            '","treasuryControlMode":"',
            config.deployClientMultisig ? "clientTreasuryMultisig" : "externalOrEoa",
            '","treasuryApprover":"',
            vm.toString(config.treasuryApprover),
            '","treasuryOperator":"',
            vm.toString(config.treasuryOperator),
            '","automationOperator":"',
            vm.toString(config.automationOperator),
            '","clientTreasuryMultisigOwners":',
            _buildAddressArrayJson(config.clientMultisigOwners),
            "}"
        );
    }

    /// @notice Builds manifest protocol-core JSON.
    /// @param config Client onboarding config.
    /// @return Protocol-core JSON fragment.
    function _buildProtocolCoreJson(ClientConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"treasuryPolicyEngine":"',
            vm.toString(config.treasuryPolicyEngine),
            '","treasuryAccountFactory":"',
            vm.toString(config.treasuryAccountFactory),
            '"}'
        );
    }

    /// @notice Builds manifest contract JSON.
    /// @param artifacts Client deployment artifacts.
    /// @return Contract JSON fragment.
    function _buildContractsJson(ClientArtifacts memory artifacts) internal pure returns (string memory) {
        return string.concat(
            '{"treasuryAutomationExecutor":"',
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

    /// @notice Builds manifest reference JSON.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    /// @return Reference JSON fragment.
    function _buildReferencesJson(ClientConfig memory config, ClientArtifacts memory artifacts)
        internal
        pure
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
            '","tigrisPoolFactory":"',
            vm.toString(config.tigrisPoolFactory),
            '","tigrisMusdMusdcPool":"',
            vm.toString(config.tigrisMusdMusdcPool),
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

    /// @notice Builds manifest scenario JSON.
    /// @param config Client onboarding config.
    /// @return Scenario JSON fragment.
    function _buildTreasuryScenarioJson(ClientConfig memory config) internal pure returns (string memory) {
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
            '","automationEnabled":',
            _jsonBool(config.automationEnabled),
            ',"startPaused":',
            _jsonBool(config.startPaused),
            "}"
        );
    }

    /// @notice Builds manifest owner-setup JSON.
    /// @param config Client onboarding config.
    /// @param artifacts Client deployment artifacts.
    /// @return Owner-setup JSON fragment.
    function _buildClientOwnerSetupJson(ClientConfig memory config, ClientArtifacts memory artifacts)
        internal
        pure
        returns (string memory)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildClientOwnerSetupBatch(config, artifacts);

        return string.concat(
            '{"executeClientOwnerSetup":',
            _jsonBool(config.executeClientOwnerSetup),
            ',"proposeClientTreasuryMultisigSetup":',
            _jsonBool(config.proposeClientMultisigSetup),
            ',"ownerSetupBatchProposed":',
            _jsonBool(artifacts.ownerSetupBatchProposed),
            ',"ownerSetupBatchId":"',
            vm.toString(artifacts.ownerSetupBatchId),
            '","clientTreasuryMultisigThreshold":"',
            vm.toString(config.clientMultisigThreshold),
            '","clientTreasuryMultisigSigDelay":"',
            vm.toString(config.clientMultisigSigDelay),
            '","clientTreasuryMultisigMaxPending":"',
            vm.toString(config.clientMultisigMaxPending),
            '","calls":',
            _buildCallsJson(targets, values, payloads),
            "}"
        );
    }

    // =============================================================
    // Utility Functions
    // =============================================================

    /// @notice Reads an address from a primary env key, then a fallback env key, then a default.
    /// @param _primary Primary environment key.
    /// @param _fallback Fallback environment key.
    /// @param _defaultValue Default address.
    /// @return value Loaded address.
    function _envAddressWithFallback(string memory _primary, string memory _fallback, address _defaultValue)
        internal
        view
        returns (address value)
    {
        value = vm.envOr(_primary, vm.envOr(_fallback, _defaultValue));
    }

    /// @notice Reads a uint64 from a primary env key, fallback env key, or default.
    /// @param _primary Primary environment key.
    /// @param _fallback Fallback environment key.
    /// @param _defaultValue Default value.
    /// @return value Loaded uint64.
    function _envUint64WithFallback(string memory _primary, string memory _fallback, uint64 _defaultValue)
        internal
        view
        returns (uint64 value)
    {
        uint256 rawValue = vm.envOr(_primary, vm.envOr(_fallback, uint256(_defaultValue)));
        if (rawValue > type(uint64).max) revert Uint64Overflow(_primary, rawValue);

        // forge-lint: disable-next-line(unsafe-typecast)
        value = uint64(rawValue);
    }

    /// @notice Returns whether an address exists in an array.
    /// @param _needle Address to find.
    /// @param _haystack Candidate address array.
    /// @return Whether `_needle` exists in `_haystack`.
    function _isAddressInArray(address _needle, address[] memory _haystack) internal pure returns (bool) {
        for (uint256 i = 0; i < _haystack.length; i++) {
            if (_haystack[i] == _needle) {
                return true;
            }
        }

        return false;
    }

    /// @notice Builds JSON for calls that must be executed by a client treasury owner.
    /// @param _targets Call targets.
    /// @param _values Native values.
    /// @param _payloads Calldata payloads.
    /// @return json JSON array string.
    function _buildCallsJson(address[] memory _targets, uint256[] memory _values, bytes[] memory _payloads)
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

    /// @notice Builds JSON for an address array.
    /// @param _addresses Addresses to encode.
    /// @return json JSON array string.
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

    /// @notice Reverts with passthrough returndata when a low-level setup call fails.
    /// @param _success Whether the call succeeded.
    /// @param _returndata Raw call returndata.
    function _revertIfCallFailed(bool _success, bytes memory _returndata) internal pure {
        if (_success) {
            return;
        }

        if (_returndata.length == 0) {
            revert("CLIENT_OWNER_SETUP_CALL_FAILED");
        }

        assembly {
            revert(add(_returndata, 32), mload(_returndata))
        }
    }

    /// @notice Converts a bool to a JSON literal string.
    /// @param _value Bool value.
    /// @return JSON bool literal.
    function _jsonBool(bool _value) internal pure returns (string memory) {
        return _value ? "true" : "false";
    }
}
