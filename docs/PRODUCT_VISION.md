# Mezo TreasuryOS — Product Vision

## Purpose

This document defines **Mezo TreasuryOS** as an institutional treasury operations product built for the **BTC Treasury Management & Institutional Services** subtrack.

The goal is not to soften the product into a simple dashboard or manual vault wrapper.
The goal is to define a version of TreasuryOS that is:

- institutional in substance
- additive to Mezo rather than duplicative
- grounded in real Mezo capital flows
- credible for a 6-week build
- strong enough to present as an almost-product rather than a prototype

---

## Product Thesis

**Mezo TreasuryOS is an institutional treasury operations layer for BTC-backed MUSD capital on Mezo.**

It wraps Mezo's native BTC-backed borrowing rail into a governed treasury workflow with:

- client-isolated Treasury Accounts
- treasury policy and approval controls
- multisig-aware execution paths
- governed allocation routing into approved Mezo-native sleeves
- accounting and reviewer-facing reporting
- bounded automated treasury operations

TreasuryOS should not be framed as a new lending protocol, a custody provider, or a proprietary yield protocol.

It should be framed as the operating system that sits on top of Mezo's capital rails and turns them into a treasury workflow.

---

## Why This Product Should Exist

Mezo makes BTC-backed borrowing possible.
That is necessary, but not sufficient, for treasury use.

A serious treasury does not just need access to borrowing.
It needs:

- a controlled operating boundary
- approval and policy enforcement
- rules for liquidity preservation
- governed allocation of idle MUSD
- operating disbursement controls
- operational monitoring
- automated treasury actions inside pre-approved limits
- accounting and reviewer visibility

Without that layer, the treasury workflow remains a loose combination of wallet actions, protocol clicks, spreadsheets, and ad hoc approvals.

TreasuryOS exists to close that gap.

---

## Product Category

This is:

- a corporate treasury workflow product
- a treasury policy and controls product
- a multisig-aware treasury operations layer
- an accounting and reporting surface for BTC-backed MUSD capital
- an automated treasury operations product

This is not:

- a custody provider
- a replacement for Mezo borrow infrastructure
- a replacement for Mezo Institutional onboarding
- a generic wallet UI
- a custom yield protocol
- an autonomous AI treasury manager

---

## Best Positioning

The strongest positioning is:

**TreasuryOS is the treasury operating layer on top of Mezo's BTC-backed borrowing rail.**

That positioning is stronger than:

- "a post-draw dashboard"
- "an institutional wrapper around Mezo"
- "a new vault product"
- "a treasury AI allocator"

It preserves institutional relevance while keeping the product clearly additive.

---

## Relationship To Mezo Institutional

TreasuryOS should not pretend Mezo Institutional does not exist.
It should explicitly position itself alongside Mezo's institutional direction.

### Where Mezo should remain primary

- BTC-backed borrow infrastructure
- core collateral and debt mechanics
- custody and qualified custody relationships
- segregated institutional vault infrastructure
- high-touch institutional onboarding

### Where TreasuryOS should become additive

- self-serve or semi-self-serve treasury workflow
- treasury policy enforcement and approval logic
- liquidity buffer management
- governed allocation of borrowed MUSD
- multisig-aware action routing
- treasury reporting and reviewer visibility
- bounded automated treasury operations

### Best differentiation line

**Mezo provides the capital rail. TreasuryOS provides the treasury operating layer that governs how that capital is used.**

This keeps the product institutional without turning it into a clone of Mezo Institutional or Enclaves.

---

## Target Customer

The best initial target is not "all institutions."

The best initial wedge is:

**BTC-heavy operating companies and treasury teams that want working capital against BTC, need internal controls and reporting, and are too operationally serious for manual DeFi workflows but not necessarily served by high-touch institutional infrastructure alone.**

This includes:

- BTC-heavy startups
- miner and mining-adjacent operating businesses
- protocol treasury teams with recurring operating needs
- BTC-native companies managing working capital and reserve liquidity

### Why this wedge is strongest

- The pain is concrete: they need liquidity without selling BTC.
- They care about treasury controls, not just access to a loan.
- They can benefit from self-serve infrastructure plus optional multisig and custody integrations.
- They are a better initial fit than trying to sell directly into the most bespoke institutional segment from day one.

---

## Core Workflow

TreasuryOS should own one full treasury workflow from start to finish:

1. Treasury creates a client-isolated **Treasury Account**
2. Treasury connects the treasury admin control path: external multisig/custody account, optional `TreasuryMultisig`, or development signer
3. Treasury deposits BTC into Mezo through the TreasuryOS-controlled workflow
4. Treasury Account opens or manages the BTC-backed MUSD position against Mezo's native mechanism
5. Minted MUSD lands into the Treasury Account
6. Treasury Policy rules determine:
   - who can act
   - what actions are allowed
   - what approvals are required
   - how much idle liquidity must remain liquid
   - which sleeves are approved
   - how much can be allocated per sleeve
7. Treasury may disburse idle MUSD for approved operating use through the required control path
8. Excess idle MUSD may be routed into approved Mezo-native sleeves
9. TreasuryOS monitors collateral state, liquidity buffer, allocation exposure, and policy conditions
10. TreasuryOS proposes or executes bounded automated actions
11. TreasuryOS produces treasury-grade activity and reviewer reports

That workflow is the product.

---

## Asset And Control Model

The product must be explicit about what it owns and what it does not own.

### What should remain Mezo-native

- BTC-backed collateral and debt mechanics
- MUSD minting and repayment logic
- destination-side yield logic
- institutional custody rails where applicable

### What TreasuryOS should own

- Treasury Account deployment and configuration
- treasury policy enforcement
- approval and signer workflow integration
- allocation routing into approved sleeves
- monitoring and automated treasury actions
- optional TreasuryOS-native multisig for users without an external control stack
- reporting and treasury state visibility

### What the Treasury Account actually is

The **Treasury Account** should be the client's isolated treasury operating boundary.

It should:

- hold treasury-managed MUSD
- own the Mezo borrow position
- hold downstream receipt assets such as `sMUSD` or approved LP tokens
- be the governed entry point for draw, allocation, disbursement, withdrawal, repayment, and close actions
- anchor policy configuration and execution permissions
- emit the events needed for reporting and reviewer visibility

It should not be presented as:

- a pooled custody account
- a TreasuryOS-owned omnibus vault
- a proprietary strategy vault

### What the treasury admin controls

The treasury admin is the authority for critical actions.

In production this can be an existing Safe, Den-backed Safe, Porto-style custody account, or another contract wallet. For onboarding and hackathon demo flows, TreasuryOS can provide an optional `TreasuryMultisig`.

The treasury admin should control:

- critical setup and dependency changes
- elevated business MUSD disbursements
- policy and automation executor configuration
- signer or owner rotation

The automation executor should not control arbitrary business withdrawals. It should only execute bounded, policy-authorized workflows such as restoring the liquid buffer or unwinding a sleeve to repay debt.

---

## Product Pillars

### 1. Treasury Account

Per-client isolated treasury operating boundary.

### 2. Treasury Policy Engine

The internal treasury control layer.

This should be described as:

- internal treasury control infrastructure
- approval and policy compliance infrastructure
- treasury rule enforcement

This is better than overclaiming legal or regulatory compliance.

### 3. Treasury Multisig / External Custody Control

TreasuryOS should support a bring-your-own control model first, while also shipping a native multisig for onboarding.

This pillar matters because the subtrack explicitly includes multi-sig treasury management, but the product should not force all users into a custom wallet.

The intended control options are:

- external Safe, Den-backed Safe, Porto-style account, or other contract wallet
- optional `TreasuryMultisig`
- EOA only for development or early testnet usage

This layer is execution authority, not policy logic. `TreasuryPolicyEngine` still decides whether actions comply with treasury rules.

### 4. Mezo Position Lifecycle

TreasuryOS should let the Treasury Account own the Mezo position lifecycle directly.

That means TreasuryOS should support:

- `openTrove`
- `adjustTrove`
- collateral add / withdrawal
- MUSD draw / repayment
- `closeTrove`

This is stronger than a thin post-draw wrapper because the debt position itself sits inside the treasury operating boundary.

### 5. Allocation Router And Sleeve Handlers

The product should use one allocation router with multiple approved sleeve handlers.

This is the right shape for treasury software because it keeps:

- one operating boundary per treasury
- one routing authority
- multiple governed downstream sleeves

Current V1 sleeves:

- **MUSD Savings Rate**
- **Tigris `MUSD/mUSDC` stable pool on Mezo testnet**

### 6. Treasury Operations Engine

This is a core part of the product, not an optional add-on.

It should provide:

- threshold monitoring
- policy-aware action checks
- idle cash sweep logic
- operating buffer restoration
- sleeve-funded debt repayment
- blocking or escalating operating disbursements that need treasury admin approval
- collateral and allocation stress detection
- bounded automated execution where allowed

### 7. Treasury Reporting Layer

Reporting should make TreasuryOS feel like real treasury software.

It should include:

- treasury position visibility
- idle vs deployed capital composition
- sleeve-level exposure reporting
- action and decision logs
- reviewer-facing summaries

---

## Allocation Model

TreasuryOS V1 should not launch its own proprietary strategy vault.

The cleanest V1 model is:

- govern treasury capital
- preserve liquidity buffer
- allow policy-checked operating disbursement from idle MUSD
- route approved idle MUSD into existing Mezo-native sleeves
- report what was deployed, where, and under what rules

### Strongest V1 sleeve strategy

Start with a router model but keep the sleeve set disciplined:

- **MUSD Savings Rate** as the primary treasury savings sleeve
- **Tigris `MUSD/mUSDC` stable pool on Mezo testnet** as the approved secondary sleeve

That gives TreasuryOS both:

- a conservative treasury idle-cash path
- a more active Mezo-native deployment path

It also avoids the wrong V1 move, which would be inventing proprietary TreasuryOS-owned yield.

---

## Institutional Substance Requirements

TreasuryOS should feel institutional because it includes:

- explicit treasury account isolation
- policy and approval logic
- operating cash disbursement controls
- multisig-aware workflow support
- allocation controls
- bounded automated actions
- treasury reporting

If TreasuryOS is implemented in that shape, it can credibly argue that it is:

- a treasury management product
- an institutional treasury workflow layer
- an automated treasury operations product
- an accounting and reporting surface for BTC-backed MUSD capital
