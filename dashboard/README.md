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

## Build And Preview

```bash
make dashboard-build
make dashboard-preview
```

This builds the static artifact at:

```text
dashboard/dist
```

Run the release readiness check:

```bash
make dashboard-vercel-check
```

That command runs dashboard syntax checks, builds `dashboard/dist`, and scans `dashboard/public` plus `dashboard/dist`
for private-key, API-key, bearer-token, and private RPC URL patterns.

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
- Framework Preset: `Other`
- Install Command: default, or `npm install`
- Build Command: `npm run build`
- Output Directory: `dist`

Manual deployment flow:

1. Regenerate data locally with `make dashboard-data`.
2. Run `make dashboard-vercel-check`.
3. Commit the sanitized `dashboard/public/data/dashboard-data.json`.
4. Import the repo in Vercel.
5. Set Root Directory to `dashboard`.
6. Confirm the settings above.
7. Deploy a preview.
8. Inspect the page and public source for secrets.
9. Promote to production only after review.
10. Add the hosted URL to the final README/runbook.

Do not configure private keys, keeper keys, OpenAI keys, deployer keys, or private RPC URLs in the hosted dashboard.
Dashboard data must be sanitized before publishing. Safe public labels such as `SPECTRUM_MEZO_RPC_URL_1` are acceptable;
actual endpoint URLs are not.
