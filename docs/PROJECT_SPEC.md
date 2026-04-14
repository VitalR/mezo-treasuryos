# Mezo TreasuryOS — Project Specification

## Purpose

This document defines the V1 product specification for **Mezo TreasuryOS** based on the updated product thesis:

**TreasuryOS is an institutional treasury operations layer for BTC-backed MUSD capital on Mezo.**

V1 should prove one complete treasury workflow:

- treasury account setup
- BTC-backed borrow initiation through TreasuryOS
- governed MUSD operating balance management
- approved allocation into a Mezo-native destination
- bounded automated treasury operations
- reporting and reviewer visibility

This spec is intended to keep the product serious, narrow, and buildable in a 6-week cycle.

---

## V1 Product Goal

The goal of V1 is not to build the full future TreasuryOS platform.

The goal is to prove that TreasuryOS can turn Mezo's native borrowing rail into a governed treasury workflow that looks credible for a real BTC-heavy company or treasury team.

V1 succeeds if a reviewer can clearly see:

- where the BTC-backed debt position lives
- where treasury-controlled MUSD lives
- what policies govern treasury actions
- how idle MUSD is allocated under constraints
- how automated treasury operations work
- what reporting and approval visibility the treasury gets

---

## Core User

The primary V1 user is:

**a BTC-heavy operating company or treasury team that wants working capital against BTC, wants to preserve BTC exposure, and needs stronger internal controls than raw protocol usage provides.**

Secondary V1 users:

- treasury operator
- treasury approver
- finance or reviewer stakeholder
- compliance or policy administrator

---

## V1 Product Thesis

V1 should solve this exact workflow:

1. treasury creates a client-isolated Treasury Account
2. treasury configures signer, approval, and treasury policy settings
3. treasury deposits BTC through TreasuryOS into Mezo's native borrow flow
4. borrowed MUSD lands into the Treasury Account
5. TreasuryOS enforces liquidity buffer and allocation rules
6. excess idle MUSD may be routed into an approved Mezo-native destination
7. TreasuryOS monitors treasury state and can trigger bounded automated actions
8. TreasuryOS produces treasury-grade logs and reviewer-facing summaries

That is the full V1 workflow.

---

## Infrastructure Requirement

V1 should use **Spectrum Nodes** as the primary Mezo testnet RPC provider.

Spectrum should support:

- treasury state reads
- borrow-position reads
- allocation and balance polling
- automated treasury operations checks
- transaction broadcasting for the live testnet workflow

This should be treated as part of the real product stack, not as a side challenge integration.

---

## System Components

V1 should include only the components needed to support the workflow above.

### 1. Treasury Account

Per-client isolated treasury operating boundary.

Responsibilities:

- receive and hold treasury-managed MUSD
- act as the execution boundary for treasury actions
- anchor policy configuration
- enforce role and action permissions
- emit treasury activity events

V1 expectation:

- one Treasury Account per treasury/client
- account isolation must be explicit in the contracts and UI

### 2. Treasury Policy Engine

The internal treasury control layer.

Responsibilities:

- validate who can perform an action
- validate which actions are allowed
- enforce approval requirements
- enforce liquidity buffer rules
- enforce allowed destination rules
- enforce allocation caps
- support action blocking or pausing

Important positioning:

- this should be described as treasury policy and internal control infrastructure
- it may support compliance-oriented workflows
- it should not overclaim broad legal or regulatory compliance coverage

### 3. Mezo Borrow Integration

TreasuryOS must wrap Mezo's native BTC-backed borrow flow.

Responsibilities:

- handle deposit plus borrow through TreasuryOS
- connect the resulting borrowed MUSD to the Treasury Account
- keep the debt-position relationship explicit in the product model
- support repayment or debt-reduction flows where needed for the demo

V1 expectation:

- borrow initiation must happen inside TreasuryOS
- users should not need to leave the product to open the core treasury position
- the live testnet borrow flow should run through the primary Spectrum-backed RPC path

### 4. Allocation Adapter

The destination integration layer for deploying idle MUSD.

Responsibilities:

- deposit into approved Mezo-native destinations
- withdraw from approved destinations
- expose destination balances for treasury state reporting

V1 expectation:

- one real primary destination adapter

Recommended first destination:

- **MUSD Savings Vault**

### 5. Treasury Operations Engine

The bounded automation and monitoring layer.

Responsibilities:

- monitor idle vs allocated MUSD
- monitor liquidity buffer state
- monitor policy-blocked or paused conditions
- monitor collateral-related treasury health signals
- prepare or trigger bounded automated actions
- produce operational explanations for actions taken or blocked

V1 expectation:

- this is a core product component, not a nice-to-have
- it should rely on Spectrum-backed reads and transaction submission in the hackathon environment

### 6. Treasury Reporting Layer

The reporting and reviewer-facing output layer.

Responsibilities:

- treasury activity timeline
- treasury state snapshot
- idle vs allocated balance view
- destination exposure summary
- policy decision log
- reviewer-facing summary output

---

## Asset And Control Model

V1 must be explicit about asset ownership and product boundaries.

### What remains Mezo-native

- collateral and debt mechanics
- MUSD minting and repayment behavior
- destination-side yield mechanics
- institutional custody rails if used

### What TreasuryOS controls

- treasury account deployment and configuration
- treasury action permissions and approval flow
- routing of approved treasury actions
- allocation policy enforcement
- automated treasury operations within policy limits
- treasury reporting and state visibility

### What the Treasury Account controls

The Treasury Account should control:

- treasury-managed MUSD balances
- approved action execution
- approved allocation and withdrawal flows
- event emission for reporting

The Treasury Account should not be framed as:

- a pooled custody layer
- a TreasuryOS-owned omnibus wallet
- a proprietary yield vault

---

## Required V1 Policies

V1 should not attempt an unlimited policy framework.

It should implement a small, defensible policy set:

### Role Policy

Defines which actors may propose, approve, or execute actions.

### Approval Policy

Defines which actions require approval and by whom.

### Liquidity Buffer Policy

Defines the minimum liquid MUSD that must remain undeployed.

### Allowed Destination Policy

Defines which destinations can receive treasury funds.

### Allocation Cap Policy

Defines the maximum amount or share that can be deployed to a destination.

### Pause Policy

Allows treasury operations to halt under explicit conditions.

Optional V1 extension:

- automation permission policy for low-risk actions

---

## Required V1 Workflows

### 1. Treasury Setup

The user must be able to:

- deploy a Treasury Account
- assign operator and approver roles
- configure policy defaults
- set liquidity buffer target
- approve one destination
- set an allocation cap

### 2. BTC Deposit Plus Borrow

The user must be able to:

- initiate the Mezo-backed borrow flow through TreasuryOS
- make the debt-position relationship visible
- receive borrowed MUSD into the Treasury Account
- view resulting treasury state
- use the primary Spectrum-backed RPC path for the live testnet flow

### 3. Governed Allocation

The user must be able to:

- identify idle MUSD above the configured buffer
- allocate only the permitted portion to the approved destination
- view resulting idle vs allocated balances

### 4. Treasury Operations

The system must be able to:

- detect excess idle MUSD
- detect buffer shortfall
- detect policy-blocked actions
- detect relevant treasury stress conditions
- propose or execute a bounded treasury action
- monitor live treasury state through the primary Spectrum-backed RPC path

### 5. Withdrawal / Buffer Restoration

The user or system must be able to:

- withdraw from the approved destination
- restore the liquid operating buffer
- record the reason for the action

### 6. Reporting

The user must be able to:

- view treasury state in one place
- view allocation and policy state
- view why actions were allowed or blocked
- view a reviewer-facing summary

---

## Automation Requirements

V1 must include automated treasury operations, but those operations must remain bounded and explainable.

### Required automation behaviors

- detect idle MUSD above threshold
- detect liquidity buffer deficit
- auto-propose or auto-trigger approved low-risk actions
- auto-block actions that violate treasury policy
- generate action rationale and state-change explanation
- use Spectrum-backed reads and transaction broadcasting for the live testnet loop

### Good V1 automated actions

- sweep idle surplus into the approved destination
- withdraw from destination to restore buffer
- halt allocation when the treasury is paused
- block new deployment when policy conditions fail

### AI guidance for V1

AI may be used for:

- explanation
- summarization
- anomaly narration
- reviewer-friendly reporting output

AI should not be the primary source of execution authority in V1.

---

## Multisig / Signer Integration

TreasuryOS should be multisig-aware in V1, even if the first implementation is narrow.

V1 expectation:

- the product model must support approver-based execution
- signer or multisig approval state should appear in the treasury workflow
- if direct live integration is too heavy, the demo may use a simplified signer-aware flow that still proves the approval concept

The key requirement is credibility of approval workflow, not the largest adapter matrix.

---

## Allocation Strategy

TreasuryOS should not promise proprietary TreasuryOS-native yield in V1.

The V1 allocation promise should be:

- governed allocation of idle MUSD
- approval and policy controls
- buffer preservation
- treasury visibility

### V1 destination set

Required:

- one real Mezo-native destination

Recommended:

- **MUSD Savings Vault**

Optional:

- one secondary destination if it materially improves the demo and remains realistic

Starting with one destination is acceptable if the product proves:

- allocation control
- treasury operations automation
- reporting value

---

## UI / Product Surface Requirements

V1 should look like one serious treasury product.

Required surfaces:

### Treasury Setup

- create Treasury Account
- configure policies and roles
- review treasury configuration before deployment

### Treasury Overview

- BTC-backed debt context
- Treasury Account state
- liquid MUSD
- allocated MUSD
- policy state
- buffer health

### Allocation View

- approved destination
- current allocation
- remaining deployable amount
- withdraw and restore actions

### Operations View

- active alerts
- recommended or automated actions
- action history
- rationale for actions taken or blocked

### Reporting View

- treasury summary
- activity timeline
- policy decision log
- reviewer-facing summary output

---

## V1 Demo Requirements

The V1 demo should prove the product from origination through treasury operations.

Required demo sequence:

1. create Treasury Account
2. configure treasury policy and approvals
3. deposit BTC and open borrow flow through TreasuryOS
4. receive MUSD into the Treasury Account
5. preserve configured liquid buffer
6. allocate surplus MUSD into the approved destination
7. trigger a treasury event or stress condition
8. show TreasuryOS proposing or executing a bounded response
9. show reviewer-facing reporting output

The demo should also make clear that:

- Spectrum Nodes powers the primary Mezo testnet RPC path for reads, monitoring, and transaction execution

The demo should make it obvious that TreasuryOS is:

- more than a dashboard
- more than a manual vault wrapper
- more than a yield surface

---

## What Must Be Cut From V1

The following should not be part of the core V1 commitment:

- proprietary TreasuryOS yield strategies
- many destination adapters
- deep accounting or ERP integrations
- a broad custody backend matrix
- cross-chain treasury orchestration
- a generalized institutional platform story beyond the core workflow
- autonomous AI execution authority

These features can be discussed as future expansion, but they should not define the V1 build.

---

## Credibility Standard

V1 is credible if it demonstrates:

- real Mezo-native borrow integration
- isolated treasury operating boundaries
- meaningful treasury policies
- multisig-aware approval posture
- one real governed allocation path
- bounded automated treasury actions
- useful treasury reporting

V1 is not credible if it only demonstrates:

- a polished dashboard
- broad architecture diagrams
- mock-only institutional language
- generic automation claims without real action logic

---

## Final V1 Definition

**Mezo TreasuryOS V1 is a client-isolated treasury operating layer that wraps Mezo's BTC-backed MUSD borrowing flow into a governed workflow with policy controls, multisig-aware approvals, one approved Mezo-native allocation path, bounded automated treasury operations, and reviewer-facing reporting.**
