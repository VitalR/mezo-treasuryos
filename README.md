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
2. configure treasury roles, approvals, and policy settings
3. deposit BTC and open a Mezo-backed MUSD position through TreasuryOS
4. receive borrowed MUSD into the Treasury Account
5. preserve a required operating liquidity buffer
6. disburse operating MUSD when needed for business use
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

- **MUSD Savings Rate**
- **Tigris `MUSD/mUSDC` stable pool on Mezo testnet**

The point of V1 is still discipline.
The product now proves one allocation routing model with two concrete Mezo-native sleeves:

- a treasury savings sleeve for idle MUSD
- a treasury LP sleeve for approved stable-pool deployment

---

## Product Components

### Treasury Account

Per-client isolated treasury operating boundary and owner of the Mezo debt position.

### Treasury Policy Engine

Internal treasury control, approval, and policy enforcement layer.

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
- disburse idle MUSD for treasury operating use
- block actions that violate treasury policy
- pause allocation when treasury conditions change
- generate clear action summaries for operators and reviewers

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

---

## Repository Docs

### Canonical docs

- [Docs Index](docs/README.md)
- [Product Vision](docs/PRODUCT_VISION.md)
- [Project Spec](docs/PROJECT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Judge Pitch](docs/JUDGE_PITCH.md)

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
