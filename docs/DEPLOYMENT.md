# Deployment Modes

This document explains the supported Treasury Account ownership modes for Mezo TreasuryOS deployments.

The deployment suite supports four onboarding paths:

- development EOA owner
- TreasuryOS-native `TreasuryMultisig` with one signer
- TreasuryOS-native `TreasuryMultisig` with two-of-three signers
- external multisig or institutional custody wallet

The product-default onboarding path should become the single-signer `TreasuryMultisig` flow. It keeps early onboarding simple while making later signer expansion a native treasury operation instead of a separate migration story.

---

## Recommended Path

Use the EOA flow while contracts, scripts, dashboard, and services are still changing quickly.

Use the single-signer `TreasuryMultisig` flow as soon as deployment/debug speed is no longer the main blocker. This should become the default demo and product onboarding mode because it proves the `multi-sig treasury management` requirement without forcing every early user into a full two-of-three setup on day one.

Avoid deploying a final demo with only an EOA owner unless the demo is explicitly framed as a development scenario.

---

## Common Requirements

All Mezo testnet deployment modes require:

```bash
MEZO_RPC_URL=<rpc url>
DEPLOYER_PRIVATE_KEY=<deployer private key>
TREASURY_APPROVER=<approver address>
TREASURY_OPERATOR=<operator address>
MEZO_MUSD_TOKEN=<MUSD token>
MEZO_BORROWER_OPERATIONS=<Mezo BorrowerOperations>
```

Optional sleeve integrations:

```bash
MEZO_MUSD_SAVINGS_RATE=<official savings vault if available>
DEPLOY_EXTERNAL_SAVINGS_MOCK=true
MEZO_TIGRIS_ROUTER=<Tigris router>
MEZO_TIGRIS_MUSD_MUSDC_POOL=<Tigris MUSD/mUSDC pool>
MEZO_MUSDC_TOKEN=<mUSDC token>
```

---

## Mode 1: Development EOA Owner

Use this while iterating quickly.

```bash
TREASURY_OWNER=<owner EOA>
TREASURY_OWNER_PRIVATE_KEY=<owner private key>
```

Run:

```bash
make deploy-mezo-testnet-eoa
```

This command deploys and verifies the stack, sets `DEPLOY_TREASURY_MULTISIG=false`, and executes owner-controlled setup directly from `TREASURY_OWNER_PRIVATE_KEY`.

Compatibility alias:

```bash
make deploy-mezo-testnet-eos
```

---

## Mode 2: Default Product Onboarding, 1-of-1 TreasuryMultisig

Use this as the default self-serve onboarding flow.

```bash
TREASURY_MULTISIG_OWNER_1=<initial signer>
TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY=<initial signer private key>
```

If `TREASURY_MULTISIG_OWNER_1` is empty, the Makefile target will use `TREASURY_OWNER` as the initial signer. If `TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY` is empty, it will use `TREASURY_OWNER_PRIVATE_KEY`.

Run:

```bash
make deploy-mezo-testnet-multisig
```

This command deploys and verifies the stack with:

```bash
DEPLOY_TREASURY_MULTISIG=true
TREASURY_MULTISIG_THRESHOLD=1
PROPOSE_TREASURY_MULTISIG_SETUP=true
```

The setup batch executes during deployment because the initial signer reaches the threshold alone.

Later, the Treasury Account owner can expand into a real multisig by proposing self-calls on `TreasuryMultisig`, such as `addOwnerWithThreshold(...)` and threshold updates. Those changes are intentionally controlled by the multisig itself, not by the Treasury Policy Engine.

---

## Mode 3: 2-of-3 TreasuryMultisig From Day One

Use this for a stronger institutional demo or a user that already has three treasury signers.

```bash
TREASURY_MULTISIG_OWNER_1=<signer 1>
TREASURY_MULTISIG_OWNER_2=<signer 2>
TREASURY_MULTISIG_OWNER_3=<signer 3>
TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY=<signer 1 private key>
```

Run:

```bash
make deploy-mezo-testnet-2of3
```

This command deploys and verifies the stack with:

```bash
DEPLOY_TREASURY_MULTISIG=true
TREASURY_MULTISIG_THRESHOLD=2
PROPOSE_TREASURY_MULTISIG_SETUP=true
```

The deployment proposer creates and confirms the setup batch. Because threshold is `2`, one additional signer must confirm the batch before owner-controlled setup is complete.

Use the `ownerSetup.ownerSetupBatchId` and `contracts.treasuryMultisig.address` from the deployment manifest:

```bash
make multisig-confirm-batch-mezo \
  MULTISIG_ADDRESS=<treasury multisig address> \
  BATCH_ID=<owner setup batch id> \
  SIGNER_PRIVATE_KEY=<second signer private key>
```

---

## Mode 4: External Multisig Or Custody Owner

Use this when the user already has a Safe, Den-backed Safe, institutional custody wallet, or another contract wallet that can execute calls.

```bash
TREASURY_OWNER=<external multisig or custody address>
```

Run:

```bash
make deploy-mezo-testnet-external
```

This command deploys and verifies the stack with:

```bash
DEPLOY_TREASURY_MULTISIG=false
EXECUTE_OWNER_CONTROLLED_SETUP=false
```

The deployment does not execute owner-only setup calls. Instead, the manifest includes `ownerSetup.calls` with each target, value, and calldata item the external multisig must execute.

That is the correct product boundary: TreasuryOS should not pretend it can operate a third-party custody or multisig account from the deployment script.

---

## Migration Guidance

For current development, using an EOA is acceptable because it reduces deployment friction.

For final demo and product positioning, prefer deploying directly into the single-signer `TreasuryMultisig` mode instead of deploying EOA-owned accounts and migrating later. Direct deployment avoids extra ownership-transfer ceremony and proves that TreasuryOS treats multisig ownership as a first-class path.

If an existing EOA-owned Treasury Account must be migrated, the expected path is:

1. deploy a `TreasuryMultisig`
2. have the EOA call `TreasuryAccount.transferOwnership(multisig)`
3. have the multisig execute `TreasuryAccount.acceptOwnership()`
4. use multisig proposals for future critical treasury actions

This migration path is viable, but it is not the cleanest default onboarding flow.

