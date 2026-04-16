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

Each manifest should include:

- `network`
- `chainId`
- `deployer`
- `treasuryPolicyEngine`
- `treasuryAccountFactory`
- `allocationRouter`
- `musdSavingsRateHandler`
- `tigrisStablePoolHandler`
- `externalMusdSavingsRateMock` when used for demo
- `references` for Mezo / Tigris dependencies

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
