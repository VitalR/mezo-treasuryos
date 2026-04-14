# Mezo TreasuryOS — Judge Pitch

## One-Line Pitch

**Mezo TreasuryOS turns Mezo's BTC-backed MUSD borrowing into a governed treasury workflow with isolated treasury accounts, policy controls, approved allocation, automated operations, and reporting.**

---

## The Problem

Mezo makes it possible to unlock dollar liquidity against BTC.

But a serious treasury does not just need access to borrowing.
It needs a way to operate that capital with:

- internal controls
- approval workflows
- liquidity preservation
- governed deployment of idle funds
- clear reporting
- automated treasury operations

Without that layer, the treasury workflow is still a loose mix of wallet actions, protocol interactions, spreadsheets, and manual coordination.

That is not treasury-grade.

---

## The Product

**TreasuryOS is the treasury operating layer on top of Mezo's capital rail.**

It gives each client:

- an isolated **Treasury Account**
- a **Treasury Policy Engine** for internal controls and approvals
- wrapped Mezo borrow origination directly through TreasuryOS
- governed allocation into approved Mezo-native destinations
- bounded automated treasury operations
- treasury reporting and reviewer visibility

For the hackathon build, TreasuryOS uses **Spectrum Nodes** as the primary Mezo testnet RPC provider for treasury state reads, monitoring, and transaction execution.

---

## How It Works

1. A treasury creates a Treasury Account in TreasuryOS.
2. The treasury configures roles, approvals, liquidity buffer, and allowed destinations.
3. The treasury deposits BTC and opens a Mezo-backed MUSD position through TreasuryOS.
4. Minted MUSD lands directly into the Treasury Account.
5. TreasuryOS keeps the required operating buffer liquid.
6. Only surplus MUSD can be allocated into approved Mezo-native destinations.
7. TreasuryOS monitors treasury conditions and proposes or executes bounded actions.
8. TreasuryOS produces reviewer-ready reporting and action logs.

---

## Why This Matters For Mezo

TreasuryOS makes Mezo more usable for:

- BTC-heavy operating companies
- treasury teams
- miner and mining-adjacent businesses
- protocol treasuries

It does not replace Mezo's borrow infrastructure.
It makes that infrastructure operationally usable for serious treasury workflows.

This directly fits the subtrack:

- corporate treasury solutions
- institutional custody integration
- accounting and reporting
- compliance and policy infrastructure
- multi-sig-aware treasury management
- automated treasury operations

---

## Why It Is Different

This is not:

- a generic dashboard
- a wallet wrapper
- a new yield protocol
- a proprietary strategy vault

This is:

- a treasury control layer
- a treasury operations layer
- a governed allocation layer
- a treasury reporting layer

### Differentiation vs Mezo Institutional

**Mezo provides the capital rail and institutional infrastructure. TreasuryOS provides the treasury operating system for governing how borrowed capital is used.**

---

## V1 Focus

V1 proves one serious workflow:

- BTC deposit and borrow through TreasuryOS
- MUSD lands into an isolated Treasury Account
- policy-governed buffer management
- one approved Mezo-native allocation path
- one automated treasury response flow
- one reviewer-facing treasury report

Recommended primary destination:

- **MUSD Savings Vault**

That keeps V1 disciplined and credible.

---

## Automation Story

TreasuryOS includes automated treasury operations, but in a bounded and explainable way.

Examples:

- sweep excess idle MUSD into the approved destination
- withdraw from the destination to restore operating buffer
- block actions that violate treasury policy
- pause allocation under stress or policy changes
- generate clear action summaries for operators and reviewers

This is treasury automation, not black-box AI capital management.

---

## Demo Story

The strongest demo is:

1. Create a Treasury Account
2. Configure policy and approvals
3. Deposit BTC and borrow MUSD through TreasuryOS
4. Show MUSD arriving into the Treasury Account
5. Keep an operating buffer and allocate only surplus MUSD
6. Trigger a stress or liquidity event
7. Show TreasuryOS restoring buffer or blocking a risky action
8. Show the reporting view explaining what happened and why

Throughout the flow, show that live reads, monitoring, and transaction execution are running through **Spectrum Nodes** on Mezo testnet.

If that flow works, TreasuryOS feels like a product, not a prototype.

---

## Final Judge Takeaway

**TreasuryOS makes Mezo's BTC-backed liquidity usable as governed treasury capital.**

It gives Mezo a product layer for treasury controls, approvals, allocation, automation, and reporting, which is exactly what serious BTC treasury users need beyond raw borrow access.
