// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BTCReservePolicy } from "../src/core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../src/core/TreasuryPolicyEngine.sol";
import { ProtocolFeeManager } from "../src/fees/ProtocolFeeManager.sol";
import { ProtocolFeeVault } from "../src/fees/ProtocolFeeVault.sol";

/// @title DeployTreasuryOSCore
/// @notice Deploys protocol-owned TreasuryOS infrastructure once for a network.
/// @dev This script intentionally does not deploy a client Treasury Account. Client onboarding is handled by
///      `OnboardTreasuryClient`, keeping protocol administration separate from user treasury ownership.
contract DeployTreasuryOSCore is Script {
    // =============================================================
    // Types
    // =============================================================

    /// @notice Protocol deployment configuration loaded from the environment.
    struct CoreConfig {
        uint256 chainId;
        uint256 deployerPrivateKey;
        address protocolAdmin;
        address musdToken;
        string manifestPath;
    }

    /// @notice Protocol deployment outputs.
    struct CoreArtifacts {
        address protocolFeeVault;
        address protocolFeeManager;
        address treasuryPolicyEngine;
        address btcReservePolicy;
        address treasuryAccountImplementation;
        address treasuryAccountFactory;
    }

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when a required environment address is zero.
    /// @param key Missing or invalid environment key.
    error InvalidAddress(string key);

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Deploys protocol core contracts and writes a core deployment manifest.
    /// @return artifacts Deployed protocol core addresses.
    function run() external returns (CoreArtifacts memory artifacts) {
        CoreConfig memory config = _loadConfig();

        console2.log("Deploying TreasuryOS protocol core to chain ID:", block.chainid);
        console2.log("Protocol admin:", config.protocolAdmin);

        vm.startBroadcast(config.deployerPrivateKey);

        ProtocolFeeVault protocolFeeVault = new ProtocolFeeVault(config.protocolAdmin);
        ProtocolFeeManager protocolFeeManager = new ProtocolFeeManager(config.protocolAdmin, address(protocolFeeVault));
        TreasuryPolicyEngine treasuryPolicyEngine = new TreasuryPolicyEngine();
        BTCReservePolicy btcReservePolicy = new BTCReservePolicy(treasuryPolicyEngine);
        TreasuryAccount treasuryAccountImplementation = new TreasuryAccount();
        TreasuryAccountFactory treasuryAccountFactory = new TreasuryAccountFactory(
            IERC20(config.musdToken), treasuryPolicyEngine, address(treasuryAccountImplementation)
        );

        artifacts.protocolFeeVault = address(protocolFeeVault);
        artifacts.protocolFeeManager = address(protocolFeeManager);
        artifacts.treasuryPolicyEngine = address(treasuryPolicyEngine);
        artifacts.btcReservePolicy = address(btcReservePolicy);
        artifacts.treasuryAccountImplementation = address(treasuryAccountImplementation);
        artifacts.treasuryAccountFactory = address(treasuryAccountFactory);

        vm.stopBroadcast();

        _writeManifest(config, artifacts);

        console2.log("ProtocolFeeVault:", artifacts.protocolFeeVault);
        console2.log("ProtocolFeeManager:", artifacts.protocolFeeManager);
        console2.log("TreasuryPolicyEngine:", artifacts.treasuryPolicyEngine);
        console2.log("BTCReservePolicy:", artifacts.btcReservePolicy);
        console2.log("TreasuryAccountImplementation:", artifacts.treasuryAccountImplementation);
        console2.log("TreasuryAccountFactory:", artifacts.treasuryAccountFactory);
        console2.log("Manifest:", config.manifestPath);
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Loads protocol deployment configuration from environment variables.
    /// @return config Protocol deployment config.
    function _loadConfig() internal view returns (CoreConfig memory config) {
        config.chainId = vm.envOr("MEZO_CHAIN_ID", block.chainid);
        config.deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        config.protocolAdmin = vm.addr(config.deployerPrivateKey);
        config.musdToken = vm.envAddress("MEZO_MUSD_TOKEN");
        config.manifestPath = vm.envOr("CORE_DEPLOYMENT_MANIFEST_PATH", string("../deployments/mezo-testnet-core.json"));

        if (config.musdToken == address(0)) revert InvalidAddress("MEZO_MUSD_TOKEN");
    }

    /// @notice Writes the core deployment manifest consumed by services and later onboarding scripts.
    /// @param config Protocol deployment config.
    /// @param artifacts Deployed protocol core addresses.
    function _writeManifest(CoreConfig memory config, CoreArtifacts memory artifacts) internal {
        string memory json = string.concat(
            "{",
            '"manifestVersion":1,',
            '"scenario":"mezo-testnet-core",',
            '"network":{"name":"Mezo Testnet","chainId":',
            vm.toString(config.chainId),
            "},",
            '"chainIdObserved":',
            vm.toString(block.chainid),
            ",",
            '"actors":{"protocolAdmin":"',
            vm.toString(config.protocolAdmin),
            '"},',
            '"contracts":{"treasuryPolicyEngine":"',
            vm.toString(artifacts.treasuryPolicyEngine),
            '","protocolFeeVault":"',
            vm.toString(artifacts.protocolFeeVault),
            '","protocolFeeManager":"',
            vm.toString(artifacts.protocolFeeManager),
            '","btcReservePolicy":"',
            vm.toString(artifacts.btcReservePolicy),
            '","treasuryAccountImplementation":"',
            vm.toString(artifacts.treasuryAccountImplementation),
            '","treasuryAccountFactory":"',
            vm.toString(artifacts.treasuryAccountFactory),
            '"},',
            '"references":{"musdToken":"',
            vm.toString(config.musdToken),
            '"}',
            "}"
        );

        vm.writeJson(json, config.manifestPath);
    }
}
