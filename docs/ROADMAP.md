# Mezo TreasuryOS — Roadmap

## Purpose

This roadmap describes how **Mezo TreasuryOS** can grow from a one-tenant Mezo testnet workflow into a treasury platform for BTC-backed operating capital.

The current submission proves the product spine:

1. a client-isolated Treasury Account;
2. BTC-backed MUSD borrowing through TreasuryOS;
3. MUSD operating-capital management;
4. policy-governed allocation into approved sleeves;
5. bounded keeper defense;
6. AI-CFO advisory reporting;
7. dashboard and audit-trail proof.

The next roadmap should not be a list of infrastructure tasks. It should answer a bigger product question:

> How does TreasuryOS become the operating system for Bitcoin treasuries on Mezo?

---

## Product Direction

TreasuryOS should become a **policy-governed treasury platform** for BTC-backed MUSD capital.

The platform direction is:

- **AI-assisted BTC treasury management**
- **automated treasury operations**
- **yield optimization across approved MUSD and BTC opportunities**
- **risk management for BTC-backed borrowing**
- **accounting, audit, and compliance-ready reporting**
- **multi-sig and external custody workflows**
- **paid treasury intelligence through x402-style service access**

The core line stays unchanged:

> The AI-CFO can recommend and prepare. Policy, multisig, and bounded executors decide what can move.

TreasuryOS should not become an unchecked AI trader, a generic yield vault, or a custody provider.

---

## Current Submission Baseline

The current Mezo testnet demo proves one live institutional treasury workflow:

- `TreasuryAccountFactory` deploys isolated client Treasury Accounts.
- One client `TreasuryAccount` is owned by a TreasuryOS-native `TreasuryMultisig`.
- BTC collateral was deposited through TreasuryOS.
- A live MUSD position was opened on Mezo testnet.
- Borrowed MUSD landed in the Treasury Account.
- MUSD was allocated to MUSD Savings through `TreasuryAccount.allocate`.
- `TreasuryPolicyEngine` proves allowed, blocked, and approval-bound decisions.
- `TreasuryAutomationExecutor` supports bounded keeper defense.
- Keeper proof includes live buffer restoration and live idle-MUSD debt repayment.
- AI-CFO proof includes live opportunity reads, deterministic ranking, blocked-opportunity explanation, and proposal packet generation.
- Dashboard proof is read-only and generated from sanitized TreasuryOS snapshots plus public Mezo testnet data.

Submission posture:

- **MUSD Savings** is the reliable live V1 sleeve.
- **Tigris MUSD/mUSDC** is contract-ready but route-health dependent on current testnet liquidity.
- **Tigris mcbBTC/BTC** is a guarded BTC-correlated yield candidate; it remains blocked in the current testnet demo until liquidity, price impact, and controlled tiny broadcast validation are acceptable.
- **Protocol fees** are deployed for future monetization, disabled by default, and not wired into treasury execution.
- **Goldsky indexing** is a reporting/indexing scaffold, not the current source of live dashboard truth.
- **Spectrum Nodes** remain the preferred Mezo testnet RPC path, with honest fallback handling when needed.

---

## Roadmap Summary

| Platform area | Next expansion | Product value | Boundary |
| --- | --- | --- | --- |
| AI-CFO robo-advisor | Client-specific AI-CFO agents with what-if planning, policy-scored recommendations, proposal packets, and post-action reports | Turns TreasuryOS into an active treasury operator assistant | AI does not sign, custody, or bypass policy |
| Automated treasury operations | Scheduled buffer reviews, debt repayment, collateral defense, surplus sweep proposals, and policy-triggered escalation | Reduces manual treasury work and improves risk response | Routine actions stay capped; elevated actions require owner approval |
| Yield optimization | More Mezo-native MUSD/BTC sleeves, Tigris routes, BTC vaults, lock/staking-style positions, and unwind-aware allocation | Helps treasuries earn on approved surplus without blindly chasing APY | Route, liquidity, price-impact, and withdrawal constraints must pass policy |
| Borrowing and risk management | Credit-line style monitoring, collateral-ratio alerts, stress tests, liquidation-defense planning, and de-risk execution paths | Makes BTC-backed leverage safer for operating treasuries | Risk-reducing actions are prioritized before yield |
| Accounting and reporting | Report packs, audit trails, policy decision history, approval evidence, and accounting exports | Makes TreasuryOS useful for finance teams, auditors, and institutional diligence | Reports reflect observed onchain state and deterministic snapshots |
| Compliance-ready controls | Destination allowlists, role policies, approval thresholds, KYB/client metadata, and restricted operating disbursements | Supports institutional treasury workflows beyond raw DeFi usage | Internal control infrastructure, not legal-compliance overclaiming |
| Mezo ecosystem expansion | Broader MUSD and BTC opportunity coverage as production-grade surfaces become available | Turns TreasuryOS into a routing and control layer for Mezo treasury capital | Integrations added only after safety and unwind validation |
| x402-paid treasury intelligence | Paid AI-CFO reports, risk snapshots, audit packs, strategy simulations, and agent-readable APIs | Creates a monetization layer for treasury intelligence | Payments gate intelligence and reporting, not custody or emergency execution |

---

## V1 — Current Product Spine

V1 proves that BTC-backed MUSD borrowing can become governed treasury capital.

### What V1 proves

- Client-isolated Treasury Account deployment
- TreasuryOS-native multisig ownership
- BTC-backed MUSD borrow flow through TreasuryOS
- Required MUSD operating buffer
- Policy-governed MUSD Savings allocation
- Keeper-driven buffer restoration
- Keeper-driven idle-MUSD debt repayment
- AI-CFO memo and proposal packet
- Read-only institutional dashboard
- Audit trail with live Mezo testnet proof

### V1 principle

TreasuryOS should protect the treasury position before chasing yield.

That means:

- preserve operating liquidity first;
- defend collateral health before new allocation;
- route only approved surplus;
- block unvalidated BTC sleeve execution;
- explain every decision.

---

## V1.1 — Productize The Treasury Workspace

The first post-submission step is not “more integrations.” It is making the one-tenant workflow usable by real operators.

### 1. Hosted report packs

Turn the read-only dashboard into a shareable treasury review surface:

- monthly treasury report;
- investment committee memo;
- keeper action summary;
- policy decision history;
- allocation exposure report;
- blocked-opportunity report.

Value:

- useful for treasury reviews;
- useful for diligence;
- useful for post-action accountability.

Boundary:

- read-only;
- no signing;
- no hidden execution.

### 2. Advisor what-if planning

Add pre-action planning before funds move:

- borrow more MUSD;
- repay debt;
- allocate surplus;
- restore buffer;
- unwind a sleeve;
- test a BTC price shock;
- compare conservative, balanced, and active profiles.

Value:

- turns AI-CFO from “memo after the fact” into a planning tool.

Boundary:

- deterministic facts first;
- LLM memo second;
- policy remains source of truth.

### 3. Proposal packets for controlled execution

Prepare proposal artifacts for the TreasuryOS-native multisig and, later, external custody or contract-wallet flows:

- calldata;
- expected state change;
- policy decision;
- risk note;
- memo hash or recommendation ID;
- approval requirement.

Value:

- bridges advisory output into real institutional execution.

Boundary:

- owner approval remains required;
- AI does not sign.

---

## V1.5 — Managed Treasury Automation

V1.5 should deepen TreasuryOS as an operations product, not just a dashboard/reporting layer.

### 1. Automated treasury operations

Expand the keeper and automation model:

- scheduled buffer checks;
- policy-triggered debt repayment proposals;
- collateral-defense recommendations;
- MUSD Savings unwind for buffer restoration;
- surplus sweep proposals;
- escalation when a routine action exceeds limits;
- one-action-per-run execution for selected defensive paths.

Value:

- reduces manual treasury work;
- improves response time under stress;
- makes BTC-backed leverage safer for operating treasuries.

Boundary:

- execution remains capped;
- emergency defense is not fee-charged;
- elevated actions require owner/multisig approval.

### 2. Goldsky-backed audit timeline

Make event history durable and queryable:

- Treasury Account creation;
- policy changes;
- allocation deposits/withdrawals;
- keeper proposals and executions;
- multisig approvals;
- AI-CFO recommendation IDs;
- blocked policy decisions.

Value:

- transforms demo proof into institutional reporting infrastructure.

Boundary:

- index observed events only;
- do not manufacture state from offchain assumptions.

### 3. External custody and contract-wallet compatibility

Support production approval workflows:

- external owner contracts;
- Safe-like contract-wallet proposal export;
- custody approval packet formats;
- spending-limit policies for routine MUSD actions;
- stricter BTC-principal approval requirements.

Value:

- moves TreasuryOS closer to institutional treasury operations.

Boundary:

- TreasuryOS provides workflow and policy;
- custody provider or client owner remains the authority.

---

## V2 — BTC Treasury Platform

V2 is where TreasuryOS becomes a broader platform for BTC-backed operating capital.

### 1. AI-CFO robo-advisor for Bitcoin treasuries

The AI-CFO should evolve from report generation into a client-specific treasury operator assistant:

- personalized treasury profiles;
- monitored objectives;
- policy-scored opportunity ranking;
- risk-aware MUSD and BTC allocation recommendations;
- what-if simulations;
- recommendation history;
- post-action explanations;
- client-specific agents with monitor, proposer, reporter, and keeper roles.

Value:

- maps directly to robo-advisors for Bitcoin portfolios;
- gives smaller treasury teams institutional-grade operating support.

Boundary:

- no AI signer;
- no AI custody;
- no arbitrary agent swaps;
- no policy bypass.

### 2. Automated yield strategies

TreasuryOS should automate the strategy review process, not blindly chase yield.

Future strategy engine:

- evaluate approved MUSD sleeves;
- evaluate BTC-denominated sleeves separately;
- compare expected yield, liquidity, lockup, and unwind conditions;
- enforce exposure caps;
- preserve operating buffer;
- prioritize de-risk actions under stress;
- prepare proposals when movement requires owner approval.

Value:

- turns yield into a governed treasury process.

Boundary:

- allocation only after route, liquidity, price-impact, and unwind checks pass;
- BTC principal requires separate BTC accounting and stronger approval.

### 3. Yield optimization across Mezo ecosystem

As the Mezo ecosystem matures, TreasuryOS can become the routing and control layer for treasury capital:

- MUSD Savings;
- Tigris stable-pool routes;
- BTC-correlated pools;
- future Mezo-native lending/yield destinations;
- external BTC vaults available on mainnet;
- lock/staking-style positions with explicit maturity and withdrawal modeling;
- LP staking and reward claim support once position accounting is stable.

Value:

- gives BTC treasuries a governed way to access more productive capital opportunities.

Boundary:

- no unvalidated integrations;
- no hidden principal risk;
- no “APY-first” UI.

### 4. Borrowing, leverage, and credit-line management

TreasuryOS can grow into a credit-line management layer for BTC-backed working capital:

- target collateral-ratio policies;
- warning and critical thresholds;
- post-stress CR modeling;
- borrow/repay planning;
- liquidation-defense runbooks;
- debt repayment automation;
- collateral top-up logic;
- close-position planning.

Value:

- makes BTC-backed borrowing operationally safer.

Boundary:

- risk-reducing actions before yield actions;
- offchain spent MUSD is not counted as defense capacity unless explicitly imported.

### 5. Institutional accounting and reporting

TreasuryOS should become the system of record for BTC-backed MUSD operating capital:

- treasury balance sheet;
- idle vs allocated MUSD;
- BTC collateral vs idle BTC reserve;
- sleeve exposure;
- receipt-token accounting;
- realized/unrealized yield estimates;
- policy decision history;
- approval evidence;
- exportable reports;
- audit-ready timelines.

Value:

- turns onchain activity into CFO, auditor, and investment-committee language.

Boundary:

- reporting should distinguish observed onchain state from estimates or assumptions.

### 6. Compliance-ready controls

TreasuryOS should support internal-control workflows without overclaiming legal compliance:

- role policies;
- destination allowlists;
- recipient allowlists;
- approval thresholds;
- operating disbursement categories;
- KYB/client metadata references;
- policy change history;
- restricted destination policies;
- exception memos.

Value:

- makes TreasuryOS credible for corporate and institutional treasury teams.

Boundary:

- internal compliance infrastructure, not legal/regulatory compliance certification.

---

## V2 Monetization And x402

TreasuryOS should monetize like treasury software, not like an extractive DeFi router.

### Primary monetization paths

- subscription for hosted monitoring and reporting;
- paid AI-CFO memo generation;
- paid report packs;
- paid API snapshots;
- paid strategy simulations;
- enterprise setup/onboarding;
- optional premium analytics;
- MEZO/MUSD subscription credits.

### x402-paid treasury intelligence

x402-style payments fit TreasuryOS best as a payment rail for read-only intelligence and reporting:

- AI-CFO reports;
- risk snapshots;
- audit packs;
- accounting exports;
- strategy simulations;
- agent-readable treasury APIs.

x402 should not gate:

- core custody;
- debt repayment;
- collateral defense;
- emergency keeper execution;
- BTC principal movement;
- MUSD buffer restoration.

The important boundary:

> x402 gates intelligence and reporting, not treasury funds.

Client BTC, MUSD, receipt tokens, and LP positions remain controlled by the Treasury Account owner, TreasuryOS-native multisig, external custody path, and bounded keeper executor.

---

## Mezo Track Alignment

TreasuryOS is centered on **BTC Treasury Management & Institutional Services**, but the roadmap intentionally touches every Mezo focus area.

| Hackathon focus area | TreasuryOS roadmap fit |
| --- | --- |
| Bitcoin Yield & Investment | Automated yield strategies, BTC vaults, staking/lock modeling, liquidity provision, yield optimization, AI-CFO robo-advisory |
| Borrowing & Leverage on BTC | BTC-backed MUSD position management, credit-line monitoring, liquidation-defense planning, collateral-ratio stress tests |
| Paying & Receiving BTC on Mezo | x402-paid treasury intelligence, report/API payments, future operating-payment workflows |
| BTC Treasury Management & Institutional Services | Corporate treasury workflows, custody/multisig controls, accounting/reporting, compliance-ready policies, automated treasury operations |

---

## What TreasuryOS Should Not Become

To keep the platform credible, TreasuryOS should avoid these traps:

- unchecked autonomous AI trading;
- proprietary “black box” yield vaults;
- routing BTC principal through MUSD accounting;
- APY-first UI that ignores liquidity and unwind risk;
- emergency-defense fee extraction;
- pretending testnet liquidity is production-safe;
- overclaiming regulatory compliance;
- replacing Mezo’s core borrowing infrastructure;
- replacing institutional custody providers.

TreasuryOS should stay focused on the operating layer:

> govern capital, defend the position, optimize approved surplus, and report the outcome.

---

## Product Milestones

### Milestone 1 — Finalized demo workspace

- hosted read-only dashboard;
- final report pack;
- public deployment manifest;
- scenario-proof runbook;
- clean public README and docs.

### Milestone 2 — Advisor planning product

- what-if simulations;
- structured recommendation packets;
- profile-based onboarding;
- proposal artifacts;
- memo hashes or recommendation IDs.

### Milestone 3 — Managed treasury automation

- scheduled monitoring;
- routine capped actions;
- escalation rules;
- post-action reports;
- indexed action history.

### Milestone 4 — Expanded Mezo yield coverage

- validated MUSD sleeves;
- BTC-correlated sleeves;
- BTC vault integrations;
- lock/staking models;
- LP staking/reward claim support where safe.

### Milestone 5 — Institutional platform readiness

- external custody and contract-wallet workflows;
- report exports;
- accounting and compliance-control modules;
- multi-tenant dashboard;
- paid treasury intelligence APIs.

---

## North Star

TreasuryOS should make BTC-backed MUSD capital usable as governed operating capital for real treasuries.

The final platform should help a treasury answer five questions:

1. How much can we borrow safely against BTC?
2. How much MUSD must remain liquid for operations and defense?
3. Which surplus can be allocated, where, and under what policy?
4. What should we do when risk changes?
5. How do we explain and prove every action to operators, finance teams, auditors, and stakeholders?

If TreasuryOS answers those questions with onchain proof, policy controls, bounded automation, and AI-assisted reporting, it becomes much more than a hackathon demo. It becomes treasury infrastructure for Bitcoin working capital on Mezo.
