# Mezo TreasuryOS — Architecture

## Purpose

This document defines the V1 architecture for **Mezo TreasuryOS** based on the current product direction.

The architecture should support one serious treasury workflow:

- client-isolated treasury setup
- BTC-backed borrow origination through TreasuryOS
- governed MUSD treasury management
- approved allocation into Mezo-native sleeves
- bounded automated treasury operations
- reviewer-facing reporting

This is not a full future-state platform blueprint.
It is the cleanest architecture that makes the V1 product credible.

---

## Architecture Principle

The V1 architecture should be:

- institutional in behavior
- narrow in scope
- explicit about asset boundaries
- simple enough to build in 6 weeks
- strong enough to look like an almost-product rather than a prototype

The system should avoid:

- too many named subsystems
- generic platform layering without clear product need
- onchain complexity that weakens auditability
- offchain sprawl that weakens delivery

---

## Core Architectural Model

TreasuryOS should sit **on top of Mezo's native borrowing and yield surfaces**.

### Mezo-native layer

This layer remains outside TreasuryOS ownership:

- BTC-backed collateral and debt mechanics
- MUSD mint / repay primitive
- destination-side yield mechanics
- custody rails where relevant

### TreasuryOS control layer

This is the product layer TreasuryOS owns:

- Treasury Account deployment
- treasury policy checks
- signer and approval workflow integration
- governed allocation routing
- treasury monitoring and automation
- treasury state and reporting

This separation is central to product credibility.

---

## V1 System Shape

The clean V1 architecture has three layers.

### Layer 1 — Onchain treasury control layer

Responsibilities:

- deploy isolated Treasury Accounts
- hold treasury-managed MUSD
- own the Mezo position lifecycle
- route allowed treasury actions
- enforce treasury policy constraints
- integrate with Mezo borrow and sleeve allocation flows
- emit treasury activity events

### Layer 2 — Offchain treasury operations layer

Responsibilities:

- index treasury state
- monitor thresholds and stress conditions
- evaluate automated action conditions
- prepare action explanations
- generate reporting outputs
- use a primary Mezo testnet RPC provider for reads, monitoring, and transaction broadcasting

### Layer 3 — Treasury product interface layer

Responsibilities:

- treasury setup flow
- approval-aware execution flow
- overview and monitoring
- operations and alert visibility
- reporting and reviewer views

---

## Onchain Components

V1 should keep the onchain system small, but not fake.

### 1. TreasuryAccountFactory

Deploys one isolated Treasury Account per client or treasury.

Responsibilities:

- deploy Treasury Account instances
- initialize treasury roles and configuration
- register required initial dependencies

Why it matters:

- makes client isolation explicit
- makes treasury setup feel like product provisioning, not just UI settings

### 2. TreasuryAccount

The core treasury operating boundary.

Responsibilities:

- receive borrowed MUSD
- own the Mezo borrow position
- hold idle treasury-managed MUSD
- execute approved disbursement, allocation, and withdrawal actions
- execute approved repay, adjust, and close-position actions
- anchor treasury policy configuration
- emit treasury activity events

Production-oriented read model:

- protocol-backed debt and collateral reads from Mezo
- consolidated treasury position snapshot
- consolidated treasury composition snapshot
- allocation decision preview for proposed surplus deployment

The Treasury Account should be:

- client-isolated
- execution-focused
- auditable

It should not become:

- a giant all-in-one strategy vault
- a pooled omnibus wallet
- a destination-specific logic dump

### 3. TreasuryPolicyEngine

The treasury internal control layer.

Responsibilities:

- validate actor permissions
- validate approval requirements
- validate liquidity buffer constraints
- validate allowed sleeve rules
- validate allocation cap limits
- enforce pause conditions
- validate automation permissions for low-risk actions

Design note:

- V1 can implement this as a dedicated module or tightly scoped policy layer
- what matters is clear control logic, not maximum modularity

### 4. TreasuryMultisig

Optional TreasuryOS-native multisig controller for client treasury administration.

Responsibilities:

- own a Treasury Account as the treasury admin authority when a user does not bring an external multisig
- receive native BTC from client custody before a multisig-approved trove-opening transaction
- forward native BTC into `TreasuryAccount.openTrove` or `TreasuryAccount.addCollateral` through approved proposals
- execute critical setup and policy-administration transactions through a signer threshold
- execute business MUSD disbursements from the Treasury Account when they require elevated treasury approval
- support batch setup transactions for onboarding and demo flows
- enforce proposal expiry, rejection, signer management, and optional confirmation delay for sensitive selectors

Design boundaries:

- it does not hold treasury funds as the primary custody boundary
- it may temporarily hold native BTC before forwarding it into the Treasury Account's Mezo position lifecycle
- it does not duplicate `TreasuryPolicyEngine` rules
- it does not execute arbitrary automated risk actions
- it can be replaced by Safe, Den-backed Safe, Porto-style custody, or another contract wallet

Why this matters:

- the subtrack explicitly asks for multi-sig treasury management
- client funds still live in the Treasury Account
- the control plane becomes realistic without forcing every demo user to set up external Safe infrastructure

### 5. AllocationRouter

The governed routing layer for downstream treasury sleeves.

Responsibilities:

- map approved destinations to handler contracts
- route treasury deposits, withdrawals, and yield claims
- authorize sleeve handlers without giving them ownership of treasury assets

Why this matters:

- one Treasury Account can support multiple sleeves
- sleeve-specific logic stays out of the account
- new MUSD-denominated sleeves can be added after deployment by registering a handler in the client-owned router and updating the account's destination policy/cap
- the product can expand without rewriting or redeploying the core treasury boundary

Boundary:

- V1 allocation accounting is MUSD-denominated. A BTC-principal sleeve would require a new asset-accounting extension, not just a new handler.

### 6. MUSDSavingsRateHandler

Primary treasury savings sleeve handler.

Responsibilities:

- route idle MUSD into Mezo's `MUSDSavingsRate`
- ensure the Treasury Account remains the holder of `sMUSD`
- claim yield back into Treasury Account idle MUSD
- expose savings-specific reporting metadata

### 7. TigrisStablePoolHandler

Secondary treasury LP sleeve handler for Mezo testnet.

Responsibilities:

- swap a portion of MUSD into the paired stable token
- add liquidity into an approved Tigris stable pool
- keep LP receipt tokens owned by the Treasury Account
- remove liquidity and swap back into MUSD on withdrawal
- expose Tigris-specific reporting metadata

Current V1 testnet target:

- Tigris `MUSD/mUSDC` stable pool on Mezo testnet

### 8. ExternalMUSDSavingsRateMock

Deployable external mock used for demo-grade savings interactions where controlled yield injection is needed.

Responsibilities:

- simulate a production-style `MUSDSavingsRate` surface
- allow owner-funded yield injection for demos
- support end-to-end treasury savings flows without pretending proprietary TreasuryOS yield

---

## Offchain Components

V1 should not split offchain logic into too many product-branded services.

It should have a small number of serious, useful services.

### RPC Infrastructure

TreasuryOS should use **Spectrum Nodes** as its primary Mezo testnet RPC provider in V1.

Spectrum should power:

- treasury state reads
- balance and position polling
- operations monitoring
- transaction broadcasting
- live dashboard state updates

Why this matters:

- it supports the real treasury operations workflow
- it strengthens the live demo
- it makes the partner-tooling integration part of the actual stack rather than a side note

### 1. Treasury State Service

Responsibilities:

- index onchain treasury activity
- aggregate Treasury Account balances and sleeve balances
- maintain treasury state model for the UI
- expose idle vs allocated composition
- expose policy state and recent decisions
- consume Spectrum-backed Mezo testnet reads for live treasury state

This may internally use indexing jobs, but it should present as one coherent service.

### 2. Treasury Operations Engine

Responsibilities:

- detect idle MUSD above threshold
- detect liquidity buffer deficit
- detect blocked or paused conditions
- detect collateral-related treasury stress signals
- recommend or trigger bounded automated actions
- explain why actions are allowed, blocked, or executed
- rely on Spectrum-backed reads and transaction submission for the live testnet workflow

This is a core product differentiator and should remain visible.

### 3. Reporting Service

Responsibilities:

- generate treasury summary outputs
- generate activity and policy logs
- generate reviewer-facing views
- produce exportable or demo-ready reporting artifacts

AI usage should remain limited to recommendation, explanation, memo drafting, and summarization support. It should consume deterministic treasury state and policy decision previews; it should not become an execution authority.

### 4. Term Yield Planner

Responsibilities:

- generate 7/30/60-day treasury allocation plans
- apply buffer constraints and sleeve caps
- include projected yield assumptions and review dates
- define unwind conditions for buffer shortfall, sleeve pressure, or collateral-health deterioration

V1 should keep this reporting-oriented. It should not introduce a Pendle-style fixed-yield protocol or new onchain yield primitive.

### 5. Treasury Advisor

Responsibilities:

- consume TreasuryOS snapshots, policy previews, sleeve capacity, and collateral-health state
- rank approved MUSD-denominated sleeves by policy capacity, risk tier, assumed yield, and unwind constraints
- recommend bounded automation actions such as buffer restoration or de-risk repayment
- generate 7/30/60-day projection assumptions for reporting

Boundary:

- this service does not sign, broadcast, custody, or execute funds
- every recommendation must map back to deterministic onchain policy and read-model state

---

## Product Interface Surfaces

V1 should present as one product, not disconnected apps.

### 1. Treasury Setup

Shows:

- treasury identity and account creation
- treasury owner selection: existing multisig/custody account, optional TreasuryOS multisig, or development EOA
- signer, operator, and approver assignment
- policy configuration
- sleeve approval and cap setup

### 2. Treasury Overview

Shows:

- debt-position context
- borrowed MUSD now held in Treasury Account
- idle vs allocated MUSD
- savings and LP sleeve exposures
- operating buffer status
- treasury policy status

### 3. Allocation View

Shows:

- approved sleeves
- deployed amount by sleeve
- remaining allocation capacity
- required liquid MUSD operating buffer
- allocatable surplus
- policy decision preview for a proposed allocation
- restore-liquidity, disbursement, or withdraw action path

### 4. Treasury Yield Console

Shows:

- idle MUSD
- required buffer
- allocatable surplus
- approved sleeves
- sleeve caps and remaining capacity
- current exposure and receipt assets
- proposed allocation decision result
- recommendation memo

This console is the main product surface for the yield angle. It should read like treasury software, not a vault APY page.

### 5. Operations View

Shows:

- alerts and threshold conditions
- recommended or executed automated actions
- rationale and action history

### 6. Reporting View

Shows:

- activity timeline
- treasury summary
- policy decision log
- reviewer-facing output
- AI-assisted treasury allocation memo
- Term Yield Planner output

---

## Asset Flow

The asset flow should be explicit and easy to explain.

### Step 1 — Treasury setup

- Treasury deploys an isolated Treasury Account through TreasuryOS
- TreasuryOS protocol admin approves/onboards the client treasury admin through the factory
- Treasury chooses the client admin control path: bring-your-own multisig/custody account or optional `TreasuryMultisig`

Protocol admin and client treasury admin are intentionally different roles. The protocol admin operates onboarding rails and registry controls; the client treasury admin owns the Treasury Account and critical treasury actions.

### Step 2 — BTC-backed borrow origination

- Client custody funds the client treasury admin, usually the `TreasuryMultisig`
- The client treasury admin executes `TreasuryAccount.openTrove` with native BTC value
- Treasury Account becomes the governed owner of the Mezo position lifecycle

### Step 3 — MUSD operating capital lands in Treasury Account

- Minted MUSD arrives in the Treasury Account as treasury-managed operating capital

### Step 4 — Treasury policy is enforced

- TreasuryOS checks role, approval, buffer, and sleeve policies before actions

### Step 5 — Operating disbursement or approved allocation

- Idle MUSD can be disbursed for operating use under policy, with larger business withdrawals executed by the treasury admin path
- Only approved surplus MUSD may be routed into approved sleeves

### Step 6 — Automated treasury response

- TreasuryOS can restore the buffer, unwind a sleeve to repay debt, block non-compliant actions, or pause riskier flows under policy

### Step 7 — Reporting

- TreasuryOS produces a clear account of treasury state, exposures, and actions taken

---

## Current Testnet Integration Targets

### Spectrum Nodes

Primary Mezo testnet RPC provider for:

- live reads
- monitoring
- transaction submission

Implementation note:

- `services/spectrum-state/rpc-health.mjs` probes `SPECTRUM_MEZO_RPC_URL_1`, `_2`, `_3`, legacy `SPECTRUM_MEZO_RPC_URL`, then `MEZO_RPC_URL`
- each candidate must answer JSON-RPC `eth_chainId` with Mezo testnet chain ID `31611`
- if no Spectrum endpoint is healthy, deployment/demo scripts fall back to `MEZO_RPC_URL` and print an honest fallback warning
- the same service reads treasury state, sleeve exposure, collateral health, and allocation-policy previews for the Yield Console and future AI memo layer

### Goldsky Indexing

Goldsky is the reporting indexer scaffold for reviewer-facing history:

- target network slug: `mezo-testnet`
- manifest: `indexer/goldsky/subgraph.yaml`
- schema: `indexer/goldsky/schema.graphql`
- mappings: `indexer/goldsky/src/mapping.ts`
- ABI directory: `indexer/goldsky/abis`

The scaffold indexes existing events only: Treasury Account deployment, policy configuration, routed savings/Tigris sleeve activity, automation executions, and multisig proposals/confirmations/executions. It should not claim blocked policy decisions as onchain events until those events actually exist. For V1 reporting, combine Goldsky event history with live Spectrum-backed state snapshots.

### Tigris stable-pool sleeve

Current official Mezo testnet targets:

- Router: `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9`
- PoolFactory: `0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A`
- `MUSD/mUSDC` pool: `0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`

These are the reference instances TreasuryOS should target for the current hackathon build.
