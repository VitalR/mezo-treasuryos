# TreasuryOS Client Treasury Workspace

Read-only institutional client treasury workspace for the Mezo TreasuryOS final demo.

The dashboard is intentionally a reporting and review surface. It does not connect a wallet, sign transactions, edit
policy, execute keeper actions, move BTC principal, or collect fees.

## Generate Data

```bash
make dashboard-data
```

This writes:

```text
dashboard/public/data/dashboard-data.json
```

The generator combines:

- internal live demo snapshots under `draft/internal/`
- deterministic treasury advisor / AI-CFO packet
- Treasury Risk Keeper live, warning, and critical reports
- current Mezo opportunity reads when RPC is available
- static opportunity fallback when live reads are unavailable
- deployed addresses from `.env`
- known live proof transactions

## Run Locally

```bash
make dashboard-dev
```

Open:

```text
http://127.0.0.1:5173
```

Set a different port with:

```bash
DASHBOARD_PORT=5174 make dashboard-dev
```

## What It Shows

- one institutional client demo tenant on Mezo testnet
- Treasury health: current CR, post-stress CR, thresholds, buffer, profile, and recommended action.
- BTC and MUSD balance sheet buckets kept separate.
- Policy and controls: TreasuryAccount, TreasuryMultisig, PolicyEngine, AutomationExecutor, AllocationRouter, handler.
- Risk Keeper state and critical proposal calldata.
- AI-CFO memo, proposal packet, blocked opportunity reasons, and guardrails.
- Yield console focused on buffer and surplus, not APY hype.
- Policy Decision Explainer for allowed, monitor, and blocked/proposal-only actions.
- Audit trail with scenario activity timeline and live transaction hashes.
- Infrastructure status: RPC, Spectrum, Goldsky scaffold, fees disabled.

## What It Does Not Do

- no wallet connect
- no transaction buttons
- no policy editing
- no BTC sleeve execution UI
- no fee payment UI
- no claim that AI controls funds
- no claim that keeper can move arbitrary assets

The product line remains: the agent is not trusted; the policy is trusted.

## Explorer Proof Links

Contract addresses link to:

```text
https://explorer.test.mezo.org/address/<address>
```

Transaction hashes link to:

```text
https://explorer.test.mezo.org/tx/<txHash>
```

Addresses and hashes stay shortened in the UI, with the full value available in the link title and copy button.

## Vercel / Static Hosting

The hosted dashboard should be treated as a static, read-only one-tenant demo workspace generated from TreasuryOS CLI
snapshots and public Mezo testnet contract data. It does not hold keys, request signatures, or broadcast transactions.

Recommended Vercel settings:

- Root Directory: `dashboard`
- Build Command: empty
- Output Directory: `public`

Do not expose `.env`, RPC URLs, private keys, or deployer/keeper secrets to the hosted dashboard. Regenerate
`dashboard/public/data/dashboard-data.json` locally before deploying when the demo state changes.
