# Mezo TreasuryOS — Product Vision V2

## Purpose

This document reframes **Mezo TreasuryOS** as an institutional treasury operations product built for the **BTC Treasury Management & Institutional Services** subtrack.

The goal is not to soften the product into a simple dashboard or manual vault wrapper.
The goal is to define a sharper version of TreasuryOS that is:

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
- governed allocation into approved Mezo-native yield destinations
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
2. Treasury connects signer or multisig approval configuration
3. Treasury deposits BTC into Mezo through the TreasuryOS-controlled workflow
4. TreasuryOS opens or manages the BTC-backed MUSD borrow position against Mezo's native mechanism
5. Minted MUSD lands into the Treasury Account
6. Treasury Policy rules determine:
   - who can act
   - what actions are allowed
   - what approvals are required
   - how much idle liquidity must remain liquid
   - which destinations are approved
   - how much can be allocated per destination
7. Excess idle MUSD may be routed into approved Mezo-native destinations
8. TreasuryOS monitors collateral state, liquidity buffer, allocation exposure, and policy conditions
9. TreasuryOS proposes or executes bounded automated actions
10. TreasuryOS produces treasury-grade activity and reviewer reports

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
- allocation routing into approved destinations
- monitoring and automated treasury actions
- reporting and treasury state visibility

### What the Treasury Account actually is

The **Treasury Account** should be the client's isolated treasury operating boundary.

It should:

- hold treasury-managed MUSD
- be the governed entry point for draw, allocation, withdrawal, and repayment actions
- anchor policy configuration and execution permissions
- emit the events needed for reporting and reviewer visibility

It should not be presented as:

- a pooled custody account
- a TreasuryOS-owned omnibus vault
- a proprietary strategy vault

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

### 3. Mezo Borrow Integration

TreasuryOS should wrap Mezo's native BTC-backed borrowing flow into a treasury-specific operating workflow rather than making users leave the product for core origination.

### 4. Allocation Adapters

Adapters should route idle MUSD only into approved Mezo-native destinations.

### 5. Treasury Operations Engine

This is a core part of the product, not an optional add-on.

It should provide:

- threshold monitoring
- policy-aware action checks
- idle cash sweep logic
- operating buffer restoration
- collateral and allocation stress detection
- bounded automated execution where allowed

### 6. Treasury Reporting Layer

Reporting should make TreasuryOS feel like real treasury software.

It should include:

- activity timeline
- treasury state snapshot
- idle vs allocated balance view
- destination exposure
- policy decision logs
- reviewer-ready summary outputs

---

## Automation Position

Automated treasury operations should remain a defining part of the product.

But the right framing is:

**bounded, policy-driven automation**

not:

- black-box automation
- autonomous AI treasury management
- strategy optimization claims without defensible logic

### Strong V1 automation examples

- auto-sweep excess idle MUSD into an approved destination
- auto-withdraw from a destination to restore operating buffer
- auto-block actions that violate policy
- auto-pause deployment when policy state changes
- auto-flag collateral stress conditions
- auto-generate treasury action and state summaries

### AI in V1

AI can be used carefully for:

- operational explanation
- action summarization
- anomaly narration
- reviewer-friendly reporting support

AI should not be the core source of authority for treasury decisions in V1.

---

## Allocation Model

TreasuryOS should **not** anchor V1 around a proprietary TreasuryOS-owned yield product.

The strongest V1 allocation model is:

- TreasuryOS governs treasury capital
- TreasuryOS defines buffer and allocation rules
- TreasuryOS routes approved idle MUSD into existing Mezo-native destinations
- TreasuryOS reports on exposure, state, and treasury actions

### Why this is the right choice

- It keeps the product aligned with Mezo rather than competitive with Mezo
- It avoids unearned strategy claims
- It makes the product look disciplined and institutional
- It keeps the story focused on treasury control, not yield marketing

### V1 destination strategy

The default V1 should be:

- one primary Mezo-native destination

Recommended first destination:

- **MUSD Savings Vault**

If a second destination is added, it should be tightly scoped and clearly secondary.

Starting with one destination is not weakness if the product proves:

- governed allocation
- liquidity preservation
- policy enforcement
- automated treasury operations

---

## V1 Product Boundary

### Must include

- Treasury Account creation
- wrapped BTC deposit plus Mezo-native borrow workflow
- treasury policy controls
- signer or multisig-aware approvals
- one real Mezo-native allocation path
- treasury operations monitoring
- bounded automated treasury actions
- accounting and reviewer-facing reporting

### Should include

- role-based approvals
- one stress scenario and one recovery scenario
- clear action reasoning in UI
- treasury state export or summary artifact

### Must not include

- proprietary TreasuryOS yield strategy
- broad destination marketplace
- deep ERP integrations
- full institutional custody stack
- cross-chain treasury expansion
- fully autonomous AI treasury management

---

## What Makes The Product Credible

TreasuryOS becomes credible if it demonstrates:

- real Mezo integration rather than mock-only product framing
- isolated client treasury boundaries
- serious internal control logic
- multisig-aware execution posture
- automation that is constrained and explainable
- reporting that looks useful to operators and reviewers

The product will not become credible by adding more architecture names or more theoretical modules.

It becomes credible by making one treasury workflow look operationally real.

---

## Demo Standard

The strongest demo should show:

1. treasury setup and Treasury Account deployment
2. BTC-backed borrow initiation through TreasuryOS
3. MUSD landing into the governed Treasury Account
4. operating buffer policy enforcement
5. approved allocation of excess MUSD into a Mezo-native destination
6. automated response to a stress or liquidity event
7. reviewer-facing treasury reporting

If this demo works, the product will feel materially stronger than a generic dashboard or simple vault wrapper.

---

## Final Positioning Statement

**Mezo TreasuryOS is an institutional treasury operations layer for BTC-backed MUSD capital on Mezo, combining isolated treasury accounts, policy controls, multisig-aware approvals, governed allocation into Mezo-native destinations, reporting, and bounded automated treasury operations.**

That is the clearest product direction for the current stage.
