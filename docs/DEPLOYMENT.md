# Deployment Modes

This document explains the supported TreasuryOS protocol administration and client Treasury Account ownership modes.

TreasuryOS has two separate control planes:

- `Protocol admin`: the TreasuryOS operator/deployer. For testnet and early development this is an EOA controlled by `DEPLOYER_PRIVATE_KEY`. It owns protocol onboarding controls such as `TreasuryAccountFactory`, treasury-admin allowlisting, and factory pause/unpause. It should not own client treasury funds.
- `Client treasury admin`: the user's treasury authority. In the product-default path this is a client-owned `TreasuryMultisig`, initially deployable as one-of-one and expandable later. It owns the user's `TreasuryAccount`, `AllocationRouter`, `TreasuryAutomationExecutor`, and critical client treasury actions.

For production, the protocol admin can later migrate to a protocol multisig. That is separate from the client multisig product surface and is not required for the hackathon deployment flow.

The deployment suite supports four onboarding paths:

- development EOA owner
- TreasuryOS-native `TreasuryMultisig` with one signer
- TreasuryOS-native `TreasuryMultisig` with two-of-three signers
- external multisig or institutional custody wallet

The product-default client onboarding path should become the single-signer `TreasuryMultisig` flow. It keeps onboarding simple while making later signer expansion a native treasury operation instead of a separate migration story.

---

## Recommended Path

Use the protocol-admin EOA flow while contracts, scripts, dashboard, and services are still changing quickly.

Use the single-signer client `TreasuryMultisig` flow as soon as deployment/debug speed is no longer the main blocker. This should become the default demo and product onboarding mode because it proves the `multi-sig treasury management` requirement without forcing every early user into a full two-of-three setup on day one.

Avoid deploying a final demo with only an EOA owner unless the demo is explicitly framed as a development scenario.

The legacy `deploy-mezo-testnet-*` script deploys protocol core and one client treasury instance together for convenience. The preferred shape is now split: deploy protocol core once, then onboard client treasury instances repeatedly.

---

## Common Requirements

Protocol core deployment requires:

```bash
MEZO_RPC_URL=<rpc url>
DEPLOYER_PRIVATE_KEY=<deployer private key>
MEZO_MUSD_TOKEN=<MUSD token>
```

For the Spectrum bonus track, set:

```bash
SPECTRUM_MEZO_RPC_URL_1=<Spectrum Mezo testnet RPC candidate>
SPECTRUM_MEZO_RPC_URL_2=<Spectrum Mezo testnet RPC candidate>
SPECTRUM_MEZO_RPC_URL_3=<Spectrum Mezo testnet RPC candidate>
MEZO_RPC_URL=https://rpc.test.mezo.org
```

TreasuryOS loads the real root `.env`, probes the Spectrum candidates first, and checks for Mezo testnet chain ID `31611`. If no Spectrum candidate is an EVM JSON-RPC endpoint for Mezo, scripts fall back to `MEZO_RPC_URL` so the demo still works.

Before deploy or demo actions, run:

```bash
make rpc-health
```

Deployment and onboarding Make targets use the selected active RPC provider internally and print only the selected provider label/env key, not the raw URL.

Goldsky reporting is scaffolded under `indexer/goldsky`. After deploying core and client contracts, copy deployed addresses and start blocks into `indexer/goldsky/subgraph.yaml`, then copy Foundry-generated ABI JSON files into `indexer/goldsky/abis/`. Do not publish the indexer with placeholder zero addresses.

Client onboarding requires:

```bash
MEZO_RPC_URL=<rpc url>
DEPLOYER_PRIVATE_KEY=<protocol admin private key>
TREASURY_POLICY_ENGINE=<deployed policy engine>
TREASURY_ACCOUNT_FACTORY=<deployed factory>
TREASURY_APPROVER=<approver address>
TREASURY_OPERATOR=<operator address>
MEZO_MUSD_TOKEN=<MUSD token>
MEZO_BORROWER_OPERATIONS=<Mezo BorrowerOperations>
```

`DEPLOYER_PRIVATE_KEY` is the protocol admin/deployer key for the current testnet suite. It deploys the factory and approves the client treasury admin in the factory. It is not the client treasury owner unless explicitly reused for a development-only EOA flow.

Optional sleeve integrations:

```bash
MEZO_MUSD_SAVINGS_RATE=0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16
DEPLOY_EXTERNAL_SAVINGS_MOCK=false
MEZO_TIGRIS_ROUTER=0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9
MEZO_TIGRIS_POOL_FACTORY=0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A
MEZO_TIGRIS_MUSD_MUSDC_POOL=0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e
MEZO_TIGRIS_MUSD_MUSDC_STABLE=true
MEZO_MUSDC_TOKEN=0xe1a26db653708A2AD8F824E92Db9852410e33A59
MEZO_BTC_TOKEN=0x7b7C000000000000000000000000000000000000
MEZO_MCBTC_TOKEN=0x2278cAAe0009E8A325A346FeA573eF23C5756dbF
MEZO_TIGRIS_MCBTC_BTC_POOL=0xc8BA1027e1D4f9C646B9963Eab89B1e7CF2A476E
MEZO_TIGRIS_MCBTC_BTC_STABLE=true
TIGRIS_MAX_SLIPPAGE_BPS=100
```

`MEZO_MUSD_SAVINGS_RATE` is the confirmed Mezo testnet MUSD Savings Vault. The displayed testnet APR is demo/testnet data, not a production guarantee. Set `DEPLOY_EXTERNAL_SAVINGS_MOCK=true` only for local deterministic scenarios.

`MEZO_TIGRIS_POOL_FACTORY` and `MEZO_TIGRIS_MUSD_MUSDC_STABLE` are required for the deployed Tigris router ABI. Swaps use a `Route[]` leg with the factory and stable flag; liquidity add/remove calls also include the stable flag. `TIGRIS_MAX_SLIPPAGE_BPS` configures the Tigris handler's minimum-output and minimum-liquidity checks. The default is `100` basis points. Do not set it to a loose value for the final demo unless the pool route actually requires it and the tradeoff is explained.

`MEZO_TIGRIS_MCBTC_BTC_POOL` is a real BTC-correlated Tigris pool target for reporting and V1.5 guarded execution. Do not wire it into the MUSD `AllocationRouter`; executable BTC allocation uses `BTCReserveRouter`, `BTCReservePolicy`, BTC-denominated receipt accounting, and separate owner/multisig approval rules.

After a client is onboarded, another MUSD-denominated sleeve can be added without redeploying the Treasury Account:

1. deploy a handler implementing `IAllocationHandler`
2. register it in the client-owned `AllocationRouter`
3. call `TreasuryPolicyEngine.updateDestinationPolicy(account, destination, true, cap)` from the client treasury admin path

This does not add native BTC-principal accounting; that remains outside V1.

Inspect RPC selection and yield target metadata before deployment:

```bash
make rpc-health
make yield-targets
```

Simulate the current Mezo yield integrations against a live Mezo testnet fork:

```bash
make mezo-yield-fork-test
```

This target reads `.env`, uses `ACTIVE_MEZO_RPC_URL` when set, otherwise falls back to `MEZO_RPC_URL`, and does not print raw RPC URLs or keys. It currently validates:

- direct MUSD Savings Vault deposit and withdrawal;
- TreasuryOS `MUSDSavingsRateHandler` deposit and withdrawal;
- TreasuryOS `TigrisStablePoolHandler` deposit and withdrawal against `MUSD/mUSDC`;
- `mcbBTC/BTC` metadata, router quote checks, guarded TreasuryOS handler fork validation, and separate BTC sleeve transaction inspection via `make btc-sleeve-targets`.

The `mcbBTC/BTC` direct and TreasuryOS-guarded add/remove-liquidity execution tests are allowed to skip when Foundry cannot execute Mezo's ERC20 BTC precompile wrapper in fork mode. Manual transaction inspection shows the UI path uses ERC20-style BTC at `0x7b7C000000000000000000000000000000000000` with `msg.value = 0`. The guarded handler now covers BTCReservePolicy checks, owner/multisig-only principal movement, swap min-out, LP min-liquidity, receipt accounting, and unwind accounting. Remaining live-demo validation is a tiny controlled testnet broadcast plus optional LP staking, unstaking, and reward-claim support.

---

## Protocol Core Deployment

Deploy protocol-owned TreasuryOS infrastructure once:

```bash
make deploy-mezo-testnet-core
```

This deploys:

- `TreasuryPolicyEngine`
- `BTCReservePolicy`
- `BTCReserveRouter` when testing V1.5 guarded BTC sleeves
- `TreasuryAccountFactory`

The owner of `TreasuryAccountFactory` is the protocol admin derived from `DEPLOYER_PRIVATE_KEY`. For testnet this should be a deployer EOA. For production it can later be migrated to a protocol multisig.

After deployment, copy the core addresses from `CORE_DEPLOYMENT_MANIFEST_PATH` into:

```bash
TREASURY_POLICY_ENGINE=<deployed policy engine>
BTC_RESERVE_POLICY=<deployed BTC reserve policy>
TREASURY_ACCOUNT_FACTORY=<deployed factory>
```

`BTCReservePolicy` governs BTC reserve bucket accounting and sleeve allow/block decisions. Configure it after onboarding if you want the demo to show BTC reserve bucket accounting, `mcbBTC/BTC` policy previews, or V1.5 guarded BTC handler validation. BTC execution still uses a separate `BTCReserveRouter`; it is not routed through the MUSD `AllocationRouter`.

---

## Client Onboarding Flow

The default onboarding path creates a client-owned `TreasuryMultisig` first:

```bash
make onboard-mezo-client-multisig
```

This deploys one client instance:

- optional client `TreasuryMultisig`, default one-of-one
- client-owned `TreasuryAutomationExecutor`
- client-owned `AllocationRouter`
- optional savings/Tigris sleeve handlers
- client-owned `TreasuryAccount` through the factory

The protocol admin only approves the client treasury admin in the factory and deploys the account through the official onboarding rail. Client setup calls are proposed through the client `TreasuryMultisig`.

The client multisig can receive native BTC and forward native BTC through approved proposals. The intended borrow flow is:

```text
client signer/custody funds TreasuryMultisig
TreasuryMultisig executes TreasuryAccount.openTrove{value: BTC}
TreasuryAccount becomes the Mezo borrower
borrowed MUSD lands in TreasuryAccount accounting
```

That means BTC should not be sent to TreasuryOS protocol admin. It should be controlled by the client treasury owner before the trove is opened.

---

## Mode 1: Development Client EOA Owner

Use this while iterating quickly.

```bash
TREASURY_OWNER=<owner EOA>
TREASURY_OWNER_PRIVATE_KEY=<owner private key>
```

Run:

```bash
make deploy-mezo-testnet-eoa
```

This command deploys and verifies the stack, sets `DEPLOY_TREASURY_MULTISIG=false`, and executes client owner-controlled setup directly from `TREASURY_OWNER_PRIVATE_KEY`.

For the split deployment flow, use:

```bash
make onboard-mezo-client-eoa
```

Compatibility alias:

```bash
make deploy-mezo-testnet-eos
```

---

## Mode 2: Default Product Onboarding, 1-of-1 Client TreasuryMultisig

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

The setup batch executes during deployment because the initial client signer reaches the threshold alone.

For the split deployment flow, use:

```bash
make onboard-mezo-client-multisig
```

Later, the Treasury Account owner can expand into a real multisig by proposing self-calls on `TreasuryMultisig`, such as `addOwnerWithThreshold(...)` and threshold updates. Those changes are intentionally controlled by the multisig itself, not by the Treasury Policy Engine.

In this mode:

- protocol admin remains the deployer EOA
- client treasury admin is the deployed `TreasuryMultisig`
- `TreasuryAccount` ownership is assigned to the client `TreasuryMultisig`
- client-owned router and automation configuration are executed through the client `TreasuryMultisig`

---

## Mode 3: 2-of-3 Client TreasuryMultisig From Day One

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

For the split deployment flow, use:

```bash
make onboard-mezo-client-2of3
```

Use the `ownerSetup.ownerSetupBatchId` and `contracts.treasuryMultisig.address` from the deployment manifest:

```bash
make multisig-confirm-batch-mezo \
  MULTISIG_ADDRESS=<treasury multisig address> \
  BATCH_ID=<owner setup batch id> \
  SIGNER_PRIVATE_KEY=<second signer private key>
```

---

## Mode 4: External Client Multisig Or Custody Owner

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

For the split deployment flow, use:

```bash
make onboard-mezo-client-external
```

The client manifest includes `clientOwnerSetup.calls` with each target, value, and calldata item the external multisig must execute.

That is the correct product boundary: TreasuryOS should not pretend it can operate a third-party custody or multisig account from the deployment script.

---

## Target Service Split

The all-in-one deploy target is acceptable for current testnet iteration, but the product should move toward two explicit scripts:

1. `DeployTreasuryOSCore`: deploys protocol-owned infrastructure once. This includes `TreasuryPolicyEngine`, `TreasuryAccountFactory`, and protocol-level references. Owner is the protocol admin EOA for testnet, later a protocol multisig.
2. `OnboardTreasuryClient`: deploys one client treasury instance. This can deploy a one-of-one `TreasuryMultisig`, create the client `TreasuryAccount` through the factory, deploy client-owned router/executor support contracts, and submit the setup batch through the client multisig.

This split matches the product model: TreasuryOS operates the onboarding rails, but the user controls their treasury account.

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
