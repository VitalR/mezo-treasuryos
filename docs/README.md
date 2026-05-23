# Mezo TreasuryOS Docs Index

This folder contains the canonical product docs for **Mezo TreasuryOS**.

These documents reflect the current product direction:

- TreasuryOS as an institutional treasury operations layer
- Treasury Account-owned Mezo position lifecycle
- isolated Treasury Accounts
- treasury policy controls
- governed allocation routing into Mezo-native sleeves
- bounded automated treasury operations
- reviewer-facing reporting

---

## Canonical Docs

- `ARCHITECTURE.md` — V1 system shape, control boundaries, and core components
- `SYSTEM_SCHEMA.md` — compact system diagrams, control boundaries, and demo-proven scenario map
- `DEPLOYMENT.md` — testnet deployment modes, ownership paths, and Makefile commands
- `PROTOCOL_FEES.md` — zero-default protocol fee architecture and future monetization model
- `DASHBOARD.md` — read-only TreasuryOS Command Center scope and dashboard data flow
- `AI_CFO_AGENT.md` — production AI-CFO / agentic treasury model and guardrails
- `ROADMAP.md` — submission status and post-hackathon product roadmap
- `BTC_RESERVE_AND_YIELD_SLEEVES.md` — BTC reserve, BTC-denominated sleeve boundaries, and future yield roadmap
- `FINAL_DEMO_RUNBOOK.md` — final judge flow, proof commands, and transaction evidence
- `MEZO_TESTNET_DEPLOYMENT.md` — active deployed addresses, verification notes, and environment values
- `TREASURY_RISK_KEEPER.md` — bounded automation and defense model

---

## Draft Boundary

Earlier exploratory notes and superseded drafts should stay out of the public docs set. The submitted docs should stay
focused on the current product, deployed demo, and control architecture.

---

## Current Naming Model

- **Product:** Mezo TreasuryOS
- **Per-client operating boundary:** Treasury Account
- **Internal controls layer:** Treasury Policy Engine
- **Borrow origination integration:** Treasury Account-owned Mezo position lifecycle
- **Operations layer:** Treasury Operations Engine
- **Destination layer:** Allocation Router + Sleeve Handlers
- **Reporting layer:** Treasury Reporting Layer
- **BTC reserve model:** BTC reserve and BTC-denominated sleeves, kept separate from MUSD operating-capital sleeves
- **AI-CFO model:** advisory and proposal preparation only; policy, multisig, and bounded keepers decide what can move

---

## Current V1 Spine

The current V1 is built around one workflow:

1. create a Treasury Account
2. configure policy and approvals
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into the Treasury Account
5. preserve required liquidity buffer
6. disburse operating MUSD where needed
7. allocate approved surplus into approved Mezo-native sleeves
8. trigger bounded automated treasury operations
9. produce treasury reporting

If the product does not support that end-to-end flow, it is outside the current V1 scope.

For a fast judge-facing architecture view, start with `SYSTEM_SCHEMA.md`.
