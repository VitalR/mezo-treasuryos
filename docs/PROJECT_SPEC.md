# Mezo TreasuryOS — Project Specification

## Purpose

This document defines the V1 product specification for **Mezo TreasuryOS** based on the current product thesis:

**TreasuryOS is an institutional treasury operations layer for BTC-backed MUSD capital on Mezo.**

V1 should prove one complete treasury workflow:

- treasury account setup
- BTC-backed borrow initiation through TreasuryOS
- governed MUSD operating balance management
- approved allocation into Mezo-native sleeves
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
- how idle MUSD is disbursed and allocated under constraints
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
2. treasury configures the treasury owner, signer, approval, and treasury policy settings
3. treasury deposits BTC through TreasuryOS into Mezo's native borrow flow
4. borrowed MUSD lands into the Treasury Account
5. TreasuryOS enforces liquidity buffer, disbursement, and allocation rules
6. treasury may disburse idle MUSD for approved operating use through the required control path
7. excess idle MUSD may be routed into approved Mezo-native sleeves
8. TreasuryOS monitors treasury state and can trigger bounded automated actions
9. TreasuryOS produces treasury-grade logs and reviewer-facing summaries

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
- own the Mezo debt position
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
- enforce allowed sleeve rules
- enforce allocation caps
- support action blocking or pausing

Important positioning:

- this should be described as treasury policy and internal control infrastructure
- it may support compliance-oriented workflows
- it should not overclaim broad legal or regulatory compliance coverage

### 3. Treasury Admin And Multisig Control

The treasury admin is the control authority for critical treasury actions.

Supported V1 control modes:

- existing Safe, Den-backed Safe, Porto-style custody account, or other external contract wallet
- optional TreasuryOS-native `TreasuryMultisig` for onboarding and demo flows
- EOA only for development or early testnet use

Responsibilities:

- own the Treasury Account when multisig control is selected
- execute critical setup actions such as borrow adapter, allocation router, and automation executor configuration
- execute elevated business MUSD disbursements from the Treasury Account
- approve or change policy settings that should not be controlled by a low-latency automation operator

Boundary:

- the multisig is an execution-control layer, not a second policy engine
- the Treasury Account remains the asset and position boundary
- the automation executor remains limited to bounded workflows approved by policy

V1 expectation:

- business withdrawals above the operator threshold should be shown as multisig-controlled
- bounded automation should remain separate and should not be able to execute arbitrary treasury withdrawals

### 4. Mezo Position Lifecycle

TreasuryOS must wrap Mezo's native BTC-backed borrow flow.

Responsibilities:

- handle deposit plus borrow through TreasuryOS
- let the Treasury Account own the Mezo position lifecycle
- connect the resulting borrowed MUSD to the Treasury Account
- keep the debt-position relationship explicit in the product model
- support repayment, collateral adjustment, and close flows

V1 expectation:

- borrow initiation must happen inside TreasuryOS
- users should not need to leave the product to open the core treasury position
- the live testnet borrow flow should run through the primary Spectrum-backed RPC path

### 5. Allocation Router And Sleeve Handlers

The destination integration layer for deploying idle MUSD.

Responsibilities:

- map approved destinations to sleeve-specific handlers
- deposit into approved Mezo-native sleeves
- withdraw from approved sleeves
- claim sleeve yield where applicable
- expose destination balances and receipt assets for treasury state reporting

V1 expectation:

- one router with two approved sleeves

Current V1 sleeves:

- **MUSD Savings Rate**
- **Tigris `MUSD/mUSDC` stable pool on Mezo testnet**

### 6. Treasury Operations Engine

The bounded automation and monitoring layer.

Responsibilities:

- monitor idle vs allocated MUSD
- monitor liquidity buffer state
- monitor operating disbursement state
- monitor policy-blocked or paused conditions
- monitor collateral-related treasury health signals
- prepare or trigger bounded automated actions
- produce operational explanations for actions taken or blocked

V1 expectation:

- this is a core product component, not a nice-to-have
- it should rely on Spectrum-backed reads and transaction submission in the hackathon environment

### 7. Treasury Reporting Layer

The reporting and reviewer-facing output layer.

Responsibilities:

- treasury activity timeline
- treasury state snapshot
- idle vs allocated balance view
- sleeve exposure summary
- policy decision log
- Treasury Yield Console data
- AI-assisted treasury memo generation
- lightweight term-yield planning output
- reviewer-facing summary output

### 8. AI Treasury Allocation Advisor

Advisory layer for treasury recommendations.

Responsibilities:

- read treasury state, policy state, allocation previews, sleeve exposure, and collateral-health signals
- generate recommendation memos and risk notes
- explain why capital is or is not allocatable
- map recommendations to allowed sleeves, buffer constraints, caps, and unwind conditions

Boundaries:

- AI does not control funds
- AI does not bypass `TreasuryPolicyEngine`
- AI does not initiate arbitrary transactions
- AI output is advisory reporting that must map back to deterministic policy state

### 9. Term Yield Planner

Planning-oriented view for treasury allocation windows.

Responsibilities:

- model 7/30/60-day allocation plans
- show projected yield assumptions without guaranteeing returns
- include maturity or review dates
- respect required operating buffer constraints
- define unwind conditions such as buffer shortfall, cap pressure, or weakening collateral health

V1 expectation:

- simulated or reporting-oriented only
- no Pendle-style fixed-yield market in V1
- no new proprietary yield primitive

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
- optional TreasuryOS-native multisig control for clients without an external signer stack
- routing of approved treasury actions
- allocation policy enforcement
- automated treasury operations within policy limits
- treasury reporting and state visibility

### What the Treasury Account controls

The Treasury Account should control:

- treasury-managed MUSD balances
- approved action execution
- approved disbursement, allocation, withdrawal, and repayment flows
- receipt assets produced by downstream sleeves
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

### Signer / Multisig Policy

Defines whether the treasury admin is an external multisig/custody account, optional `TreasuryMultisig`, or development EOA.

This is a client treasury control policy, not TreasuryOS protocol administration. The protocol admin may remain an EOA during testnet development, while the user's Treasury Account is still owned and operated by a client multisig.

### Approval Policy

Defines which actions require approval and by whom.

### Liquidity Buffer Policy

Defines the minimum liquid MUSD that must remain undeployed.

### Allowed Sleeve Policy

Defines which sleeves or destinations can receive treasury funds.

### Allocation Cap Policy

Defines the maximum amount or share that can be deployed to a sleeve.

### Pause Policy

Allows treasury operations to halt under explicit conditions.

Optional V1 extension:

- automation permission policy for low-risk actions

---

## Required V1 Workflows

### 1. Treasury Setup

The user must be able to:

- deploy a Treasury Account
- select the treasury admin control path
- configure or attach a multisig/custody account for critical actions where applicable
- assign operator and approver roles
- configure policy defaults
- set liquidity buffer target
- approve sleeves
- set allocation caps

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
- allocate only the permitted portion to approved sleeves
- view resulting idle vs allocated balances
- preview whether a proposed allocation is allowed or blocked
- see the reason for a blocked allocation, including buffer breach, cap breach, unapproved sleeve, insufficient idle MUSD, or approval requirement

### 4. Treasury Disbursement

The user must be able to:

- disburse idle MUSD from the Treasury Account to an approved external recipient
- enforce approval thresholds on operating disbursement
- require the treasury admin path, usually a multisig/custody account, for elevated business withdrawals
- preserve the configured liquid buffer unless a higher-authority actor approves the action

### 5. Treasury Operations

The system must be able to:

- detect excess idle MUSD
- detect buffer shortfall
- detect policy-blocked actions
- detect relevant treasury stress conditions
- propose or execute a bounded treasury action
- monitor live treasury state through the primary Spectrum-backed RPC path

### 6. Withdrawal / Buffer Restoration

The user or system must be able to:

- withdraw from an approved sleeve
- restore the liquid operating buffer
- record the reason for the action

### 7. Reporting

The product must be able to:

- show a treasury state summary
- show idle vs allocated capital
- show sleeve exposures and receipt assets
- show policy decisions and action history
- show a Treasury Yield Console with buffer, surplus, caps, exposure, and policy decision result
- generate an AI-assisted treasury memo that explains current position, idle versus allocated MUSD, sleeve exposure, policy decisions, automation actions, and recommended next step
- show term-yield planning assumptions for 7/30/60-day allocation windows
- provide reviewer-facing treasury context

---

## V1 Proof Standard

V1 should not try to prove everything.
It should prove the following, clearly:

- client-isolated Treasury Account deployment
- TreasuryOS-driven BTC-backed borrow origination
- policy-checked treasury operations
- multisig-managed critical setup and business MUSD disbursement
- multi-sleeve governed allocation
- one bounded automated treasury response
- policy-aware yield allocation console and advisory memo
- reviewer-facing treasury reporting
