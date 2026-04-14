# Mezo TreasuryOS — Architecture

## Purpose

This document defines the V1 architecture for **Mezo TreasuryOS** based on the updated product direction.

The architecture should support one serious treasury workflow:

- client-isolated treasury setup
- BTC-backed borrow origination through TreasuryOS
- governed MUSD treasury management
- approved allocation into a Mezo-native destination
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
- route allowed treasury actions
- enforce treasury policy constraints
- integrate with Mezo borrow and allocation flows
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

V1 should keep the onchain system small.

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
- hold idle treasury-managed MUSD
- execute approved allocation and withdrawal actions
- execute approved repay or debt-management actions if included
- anchor treasury policy configuration
- emit treasury activity events

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
- validate allowed destination rules
- validate allocation cap limits
- enforce pause conditions
- validate automation permissions for low-risk actions

Design note:

- V1 can implement this as a dedicated module or tightly scoped policy layer
- what matters is clear control logic, not maximum modularity

### 4. MezoBorrowAdapter

The adapter that wraps Mezo's native BTC-backed borrow flow for TreasuryOS.

Responsibilities:

- route deposit plus borrow actions through TreasuryOS
- keep the debt-position relationship visible in the system model
- connect minted MUSD flows to the Treasury Account
- support repay or unwind path if needed for the core demo

This component is what upgrades TreasuryOS from a post-draw wrapper into a true treasury operating layer.

### 5. SavingsVaultAdapter

Primary V1 allocation adapter for the Mezo-native destination.

Responsibilities:

- deposit MUSD into the approved savings destination
- withdraw MUSD to restore treasury liquidity
- expose destination balance state for reporting

V1 recommendation:

- keep one primary destination adapter
- prove disciplined allocation rather than broad adapter coverage

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
- aggregate Treasury Account balances and adapter balances
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

AI usage, if any, should remain limited to explanation and summarization support.

---

## Product Interface Surfaces

V1 should present as one product, not disconnected apps.

### 1. Treasury Setup

Shows:

- treasury identity and account creation
- signer or approver assignment
- policy configuration
- initial destination approval and cap setup

### 2. Treasury Overview

Shows:

- debt-position context
- borrowed MUSD now held in Treasury Account
- idle vs allocated MUSD
- operating buffer status
- treasury policy status

### 3. Allocation View

Shows:

- approved destination
- deployed amount
- remaining allocation capacity
- restore-liquidity or withdraw action path

### 4. Operations View

Shows:

- alerts and threshold conditions
- recommended or executed automated actions
- rationale and action history

### 5. Reporting View

Shows:

- activity timeline
- treasury summary
- policy decision log
- reviewer-facing output

---

## Asset Flow

The asset flow should be explicit and easy to explain.

### Step 1 — Treasury setup

- Treasury deploys an isolated Treasury Account through TreasuryOS

### Step 2 — BTC-backed borrow origination

- Treasury initiates deposit plus borrow through TreasuryOS
- TreasuryOS routes the action into Mezo's native borrow mechanism

### Step 3 — MUSD operating capital lands in Treasury Account

- Minted MUSD arrives in the Treasury Account as treasury-managed operating capital

### Step 4 — Treasury policy is enforced

- TreasuryOS checks role, approval, buffer, and destination policies before actions

### Step 5 — Approved allocation

- Only idle MUSD above the required buffer may be routed into the approved destination

### Step 6 — Automated treasury response

- TreasuryOS monitors conditions and proposes or performs bounded actions such as:
  - idle cash sweep
  - buffer restoration
  - action blocking
  - allocation pause

### Step 7 — Reporting

- TreasuryOS records and surfaces treasury state, actions, and policy outcomes

---

## Control Boundary Decisions

### What must stay onchain

- Treasury Account isolation
- treasury action execution
- treasury policy enforcement
- approval-aware action gating
- allocation and withdrawal execution
- treasury activity events

### What should stay offchain

- threshold monitoring
- reporting logic
- reviewer summary generation
- automation orchestration
- alerting and explanation
- RPC-backed state reads and transaction broadcasting

### Why

This keeps:

- critical fund controls deterministic and auditable
- the treasury workflow explainable
- operations and reporting flexible
- V1 complexity within reach
- the Spectrum Nodes integration attached to real product behavior rather than generic infra

---

## Required V1 Architectural Behaviors

The system must support:

- isolated Treasury Account deployment
- borrow origination through TreasuryOS
- policy-blocked and policy-allowed actions
- one approved destination allocation path
- liquidity buffer preservation
- one automated treasury response flow
- one reporting flow that ties actions to state changes

If the architecture cannot support those behaviors cleanly, it is too abstract.

---

## What V1 Must Not Become

V1 should not become:

- a vault marketplace
- a giant modular contract system
- a generalized institutional custody stack
- a multi-destination strategy framework
- an AI-native treasury decision engine

Those directions increase complexity faster than they increase credibility.

---

## Mainnet-Conscious Design

Even in V1, the system should look like it could mature into production after security review and operational hardening.

That means:

- client isolation is explicit
- treasury control logic is deterministic
- adapter boundaries are clear
- asset ownership is legible
- automated actions are bounded
- reporting is tied to real execution state

For the hackathon build, the Mezo testnet path should be explicitly powered by **Spectrum Nodes** as the primary RPC provider for state reads, monitoring, and transaction submission.

The architecture should look like treasury software built on top of Mezo, not a hackathon-only shell around protocol calls.

---

## Final Architecture Statement

**TreasuryOS V1 should use a small onchain control layer and a focused offchain operations layer to turn Mezo's BTC-backed borrow rail into a governed treasury workflow with isolated accounts, treasury policy enforcement, one approved allocation path, bounded automation, and reporting.**
