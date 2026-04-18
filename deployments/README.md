# Deployments

This folder contains deployment outputs and network-specific manifests for **Mezo TreasuryOS**.

---

## Intended Contents

Deployment manifests in this folder should capture:

- deployed TreasuryOS contract addresses
- the target network and chain ID
- the Mezo and Tigris addresses used during deployment
- the router-to-handler sleeve mapping
- deployment block numbers
- git commit or version reference

---

## Recommended Manifest Shape

Use one file per network and scenario, for example:

- `mezo-testnet.json`
- `mezo-testnet-demo.json`
- `mezo-testnet-demo.template.json`

Each manifest should include:

- `network`
- `chainId`
- `deployer`
- `treasuryPolicyEngine`
- `treasuryAccountFactory`
- `treasuryAutomationExecutor`
- `allocationRouter`
- `musdSavingsRateHandler`
- `tigrisStablePoolHandler`
- `externalMusdSavingsRateMock` when used for demo
- `references` for Mezo / Tigris dependencies

The repo now includes a starter template:

- `mezo-testnet-demo.template.json`

---

## Source Inputs

Deployments should be parameterized from:

- `config/mezo-testnet.json`
- root `.env`

The checked-in config provides public addresses.
The `.env` file provides RPC URLs, private keys, and any unresolved deployment overrides.

---

## Current Testnet Assumptions

Current testnet deployment planning assumes:

- Mezo Testnet, chain ID `31611`
- Spectrum Nodes as the primary RPC provider
- Mezo MUSD borrow contracts from official docs
- Tigris testnet router and `MUSD/mUSDC` stable pool from official docs

The savings vault address is intentionally not pinned here yet unless it has been confirmed in the deployment environment.

If a live official testnet savings contract is unavailable or not yet confirmed, the demo deployment may use:

- `ExternalMUSDSavingsRateMock`

That keeps the sleeve behavior realistic without inventing TreasuryOS-native yield.

---

## Template Usage

Start from:

- `deployments/mezo-testnet-demo.template.json`

Then fill in:

- deployed TreasuryOS contract addresses
- deployer and owner addresses
- block numbers
- git commit reference
- the actual savings sleeve reference used for the scenario

If the demo uses the external savings mock, keep:

- `references.musd.savingsRate.address` empty
- `contracts.externalMusdSavingsRateMock.address` filled

If the demo uses an official Mezo testnet savings contract, do the opposite.

---

## Deployment Script

The repo now includes a Foundry deployment entrypoint:

- `contracts/script/DeployTreasuryOS.s.sol`

Typical local usage:

```bash
set -a
. ./.env
set +a
forge script script/DeployTreasuryOS.s.sol:DeployTreasuryOS --root contracts --rpc-url "$MEZO_RPC_URL" --broadcast
```

The script:

- deploys the core TreasuryOS contracts
- deploys a bounded `TreasuryAutomationExecutor`
- optionally deploys `ExternalMUSDSavingsRateMock` when no official savings address is set
- optionally deploys the Tigris handler when the paired stable token address is configured
- deploys one demo Treasury Account through the factory
- writes a deployment manifest to `DEPLOYMENT_MANIFEST_PATH`
