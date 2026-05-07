# Mezo TreasuryOS

**Mezo TreasuryOS** is an institutional treasury operations layer for BTC-backed MUSD capital on Mezo.

It turns Mezo's native BTC-backed borrowing flow into a governed treasury workflow with:

- isolated Treasury Accounts
- treasury policy and approval controls
- multisig-aware execution paths
- approved allocation routing into Mezo-native sleeves
- bounded automated treasury operations
- accounting and reviewer-facing reporting

TreasuryOS is not a custody provider, not a generic dashboard, and not a proprietary yield protocol. It is the treasury operating layer on top of Mezo's capital rails.

---

## Why This Exists

Mezo makes it possible to unlock MUSD liquidity against BTC.

That is the capital rail.

A serious treasury still needs:

- internal controls
- approval workflows
- liquidity buffer management
- governed deployment of idle MUSD
- operating cash disbursements
- automated treasury operations
- reporting and reviewer visibility

Without that layer, treasury operations remain a loose combination of protocol actions, wallet flows, manual approvals, and spreadsheets.

TreasuryOS exists to turn that into a treasury workflow.

---

## Product Thesis

**TreasuryOS is the treasury operating layer on top of Mezo's BTC-backed borrowing rail.**

It is designed for:

- BTC-heavy operating companies
- miner and mining-adjacent businesses
- treasury teams managing BTC-backed working capital
- protocol treasuries with operating liquidity needs

The product should feel institutional in posture without pretending to replace Mezo's own borrow, custody, or institutional infrastructure.

### Differentiation vs Mezo Institutional

**Mezo provides the capital rail and institutional infrastructure. TreasuryOS provides the treasury operating system for governing how borrowed capital is used.**

---

## Core Workflow

TreasuryOS is built around one end-to-end workflow:

1. deploy a client-isolated **Treasury Account**
2. configure treasury owner, roles, approvals, and policy settings
3. deposit BTC and open a Mezo-backed MUSD position through TreasuryOS
4. receive borrowed MUSD into the Treasury Account
5. preserve a required operating liquidity buffer
6. disburse operating MUSD through the approved treasury control path
7. allocate only approved surplus MUSD into approved Mezo-native sleeves
8. monitor treasury conditions and trigger bounded automated actions
9. generate treasury-grade reporting and reviewer summaries

That workflow is the center of the product.

---

## V1 Focus

The V1 build is intentionally narrow.

It aims to prove:

- real Mezo borrow integration
- per-client treasury isolation
- treasury policy enforcement
- multi-sleeve governed allocation
- automated treasury operations
- reporting that looks useful to operators and reviewers

### V1 sleeve set

- **MUSD Savings Vault** at `0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`
- **Tigris Basic Stable `MUSD/mUSDC` pool** at `0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`

The point of V1 is still discipline.
The product now proves one allocation routing model with two concrete Mezo-native sleeves:

- a treasury savings sleeve for idle MUSD
- a treasury LP sleeve for approved stable-pool deployment

The yield angle is not a separate high-yield product. TreasuryOS preserves the required operating buffer first, calculates allocatable surplus, previews the policy decision for proposed sleeve allocations, and routes only approved surplus into capped Mezo-native sleeves.

`MUSD/mUSDC` has a passing live-fork TreasuryOS deposit/withdraw simulation, but MUSD Savings remains the primary demo sleeve because testnet LP liquidity can move or become imbalanced. BTC reserve and BTC-denominated yield are treated separately from MUSD operating capital. V1 includes `BTCReservePolicy` for reserve bucket accounting and preview-only BTC sleeve decisions, so the advisor can discuss the real Tigris `mcbBTC/BTC` pool candidate without implying BTC-principal execution is live. See `docs/BTC_RESERVE_AND_YIELD_SLEEVES.md`.

---

## Deployment Modes

TreasuryOS supports four Treasury Account ownership paths:

- development EOA owner: `make deploy-mezo-testnet-eoa`
- default product onboarding with single-signer `TreasuryMultisig`: `make deploy-mezo-testnet-multisig`
- two-of-three `TreasuryMultisig`: `make deploy-mezo-testnet-2of3`
- external multisig or custody owner: `make deploy-mezo-testnet-external`

The recommended path is EOA for fast development and single-signer `TreasuryMultisig` for final demo/product onboarding. See `docs/DEPLOYMENT.md` for exact environment variables and setup steps.

---

## Product Components

### Treasury Account

Per-client isolated treasury operating boundary and owner of the Mezo debt position.

### Treasury Policy Engine

Internal treasury control, approval, and policy enforcement layer.

### Treasury Multisig

Optional TreasuryOS-native multisig controller for demos and self-serve onboarding.

Production users can also bring an existing Safe, Den-backed Safe, Porto-style custody account, or any contract wallet as the Treasury Account owner. TreasuryOS only needs a contract or signer-controlled address that can execute critical treasury actions.

### Mezo Position Lifecycle

`TreasuryAccount` owns the Mezo position lifecycle directly, including borrow, adjust, repay, collateral changes, and close.

### Allocation Router And Handlers

Governed routing of idle MUSD into approved Mezo-native sleeves.

Current handlers:

- `MUSDSavingsRateHandler`
- `TigrisStablePoolHandler`

### Treasury Operations Engine

Monitoring and bounded automated treasury actions.

### Treasury Reporting Layer

Treasury state, activity, policy, sleeve exposure, and reviewer-facing reporting outputs.

### Treasury Yield Console And AI Memo

Product/reporting surface for idle MUSD, required buffer, allocatable surplus, approved sleeves, caps, exposure, BTC reserve/collateral context, policy decision results, and advisory treasury memos.

AI can explain and recommend. It cannot sign, bypass policy, or control funds.

Demo renderer:

```sh
npm run demo:yield-console
npm run advisor:demo
npm run demo:term-planner
```

Live RPC state probe:

```sh
npm run rpc-health
npm run state:probe
npm run yield:targets
make mezo-yield-fork-test
```

The state reader loads the real `.env`, tests `SPECTRUM_MEZO_RPC_URL_1`, `_2`, `_3`, then the legacy `SPECTRUM_MEZO_RPC_URL`, and falls back to `MEZO_RPC_URL` only if no Spectrum candidate returns Mezo testnet chain ID `31611`. We should not claim Spectrum was active in a given run unless `make rpc-health` reports a Spectrum endpoint as `OK`.

Sleeve extensibility:

TreasuryOS can add another MUSD-denominated sleeve after deployment by deploying a handler, registering it in the client-owned `AllocationRouter`, and updating the account's destination policy/cap in `TreasuryPolicyEngine`. Native BTC-principal sleeve accounting is not part of V1.

The deterministic advisor service consumes treasury snapshots and recommends allocation/automation actions across approved MUSD sleeves while reporting BTC reserve and BTC-denominated sleeve candidates separately. It is a reporting layer only; it does not control funds or bypass policy checks.

Goldsky indexing scaffold:

```sh
ls indexer/goldsky
```

The scaffold targets `mezo-testnet` and indexes real TreasuryOS events for account creation, policy updates, sleeve activity, automation, and multisig approvals. It is intentionally not published until deployed contract addresses, start blocks, and Foundry-generated ABIs are copied in.

---

## Automation Position

Automated treasury operations are a core part of the product.

The intended model is:

- bounded
- explainable
- policy-driven
- approval-aware

Examples:

- sweep excess idle MUSD into an approved sleeve
- withdraw from a sleeve to restore operating buffer
- withdraw from a sleeve and repay debt during a bounded de-risk workflow
- block actions that violate treasury policy
- pause allocation when treasury conditions change
- generate clear action summaries for operators and reviewers

Business MUSD disbursements are critical treasury actions. In the intended control model, larger operating withdrawals are executed by the treasury admin path, usually a multisig or institutional custody account, not by the automation executor.

AI, if used, should support explanation and summarization. It should not be the primary authority for treasury decisions in V1.

---

## Asset And Control Model

TreasuryOS should be explicit about what it owns and what it does not own.

### Mezo-native

- BTC-backed collateral and debt mechanics
- MUSD minting and repayment behavior
- destination-side yield logic
- custody rails where relevant

### TreasuryOS-owned product layer

- Treasury Account deployment and configuration
- treasury policy enforcement
- approval and signer workflow integration
- allocation routing and sleeve handling
- monitoring and bounded automation
- reporting and reviewer visibility

The Treasury Account is a client-isolated treasury operating boundary. It is not a TreasuryOS omnibus custody vault and not a proprietary strategy product.

In the current implementation, the Treasury Account owns:

- the Mezo debt position
- borrowed MUSD
- `sMUSD` receipt tokens from the savings sleeve
- LP receipt tokens from approved Tigris stable-pool sleeves

The Treasury Account owner is the treasury admin authority. That owner can be:

- an existing Safe, Den-backed Safe, Porto-style account, or other external multisig/custody account
- the optional `TreasuryMultisig` shipped with TreasuryOS for onboarding and demo flows
- an EOA only for local development or early testing

Critical setup and business-cash withdrawals should flow through that owner. Automation is intentionally narrower: it can only run specific bounded workflows such as buffer restoration or sleeve-funded debt repayment after the policy engine has authorized the executor.

---

## Repository Docs

### Canonical docs

- [Docs Index](docs/README.md)
- [Product Vision](docs/PRODUCT_VISION.md)
- [Project Spec](docs/PROJECT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Judge Pitch](docs/JUDGE_PITCH.md)

### Operational references

- [Config](config/README.md)
- [Deployments](deployments/README.md)
- [Deployment env requirements](docs/DEPLOYMENT.md)
- [Mezo testnet demo manifest template](deployments/mezo-testnet-demo.template.json)

### Draft archive

- [Archived V1 docs and earlier drafts](draft/docs/README.md)

---

## V1 Credibility Standard

TreasuryOS V1 is credible if it demonstrates:

- real Mezo-native borrow origination through the product
- isolated Treasury Account boundaries
- meaningful treasury policy controls
- real governed allocation through the router
- two concrete approved sleeves
- one real automated treasury response
- reporting that explains what happened and why

If it only demonstrates a polished dashboard or generic vault wrapper, it fails its own thesis.

---

## Summary

**Mezo TreasuryOS is a treasury operations product, not just a protocol wrapper.**

The product's job is to make BTC-backed MUSD usable as governed treasury capital on Mezo through policy controls, approved allocation, automated treasury operations, and reporting.
