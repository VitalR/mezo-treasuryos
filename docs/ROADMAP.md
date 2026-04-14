# Mezo TreasuryOS — Roadmap

## Purpose

This roadmap defines the build sequence for **Mezo TreasuryOS V1** under the updated product direction.

The roadmap is designed for a serious 6-week build where the output should look like:

- a real treasury product
- tightly integrated with Mezo
- institutional in posture
- narrow enough to finish

This roadmap intentionally avoids expanding into a broad future-platform program.

---

## V1 Build Objective

By the end of the build, TreasuryOS should demonstrate one full treasury workflow:

1. create a Treasury Account
2. configure treasury roles and policy settings
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into the Treasury Account
5. preserve a configured operating buffer
6. allocate approved surplus MUSD into one Mezo-native destination
7. trigger a stress or liquidity condition
8. show a bounded automated treasury response
9. produce reviewer-facing reporting

If that workflow works end to end, the build is successful.

---

## Build Strategy

The roadmap should follow one rule:

**build the product spine first**

The product spine is:

- Treasury Account
- Mezo borrow integration
- Treasury Policy Engine
- one allocation adapter
- one automation loop
- one reporting loop

Anything that does not strengthen that spine should be deferred.

---

## Phase 0 — Product Lock And Reference Validation

### Goals

- lock the V2 product thesis
- lock the V1 workflow
- lock naming and positioning
- confirm the Mezo integration surfaces to use
- lock the primary Mezo testnet RPC provider
- reduce ambiguity before implementation starts

### Deliverables

- `PRODUCT_VISION.md`
- `PROJECT_SPEC.md`
- `ARCHITECTURE.md`
- `JUDGE_PITCH.md`
- confirmed integration assumptions for Mezo borrow and first destination
- Spectrum Nodes selected and documented as the primary Mezo testnet RPC provider

### Success criteria

- the team can explain the product in one clear sentence
- the V1 workflow is concrete and stable
- the first destination is locked
- the RPC decision is locked early enough to shape the monitoring and demo stack
- the product is clearly differentiated from Mezo Institutional without retreating from the subtrack

---

## Phase 1 — Treasury Control Foundation

### Goals

- implement client-isolated Treasury Account deployment
- implement the initial Treasury Policy Engine
- define roles, approvals, and treasury action boundaries
- establish event model for state and reporting
- prepare the event and read model for Spectrum-backed treasury state services

### Deliverables

- `TreasuryAccountFactory`
- `TreasuryAccount`
- initial `TreasuryPolicyEngine`
- unit tests for account isolation and policy enforcement
- treasury event schema
- RPC and event-read assumptions documented for Spectrum-backed state consumption

### Success criteria

- a new treasury can deploy an isolated Treasury Account
- basic treasury roles and permissions are enforceable
- at least the core policies are working:
  - role policy
  - approval policy
  - liquidity buffer policy
  - allowed destination policy
  - allocation cap policy

---

## Phase 2 — Borrow Origination Through TreasuryOS

### Goals

- integrate Mezo-native BTC-backed borrow flow into TreasuryOS
- make TreasuryOS the product entry point for treasury origination
- ensure borrowed MUSD lands into the Treasury Account
- wire Spectrum Nodes into testnet reads and transaction broadcasting for this flow

### Deliverables

- `MezoBorrowAdapter`
- integration tests covering deposit plus borrow flow
- state model showing debt-position context and Treasury Account MUSD state
- Spectrum-backed RPC configuration for borrow-related reads and writes

### Success criteria

- treasury can initiate deposit plus borrow without leaving TreasuryOS
- minted MUSD arrives in the Treasury Account
- the product clearly shows the relationship between the borrow position and treasury-managed MUSD
- the testnet borrow workflow is running through Spectrum Nodes as the primary RPC path

### Notes

This phase is strategically critical.
If borrow origination is weak or fake, the whole product becomes a post-draw shell again.

---

## Phase 3 — Governed Allocation Layer

### Goals

- add one real Mezo-native allocation path
- enforce buffer and destination rules on allocation
- support deposit and withdrawal for treasury operations

### Deliverables

- primary allocation adapter
- destination state tracking
- governed allocation UI flow
- integration tests for deploy and withdraw behavior
- Spectrum-backed polling for destination and treasury balance state

### Recommended V1 destination

- **MUSD Savings Vault**

### Success criteria

- only permitted surplus MUSD can be allocated
- allocation cap rules are enforced
- the product can withdraw from the destination to restore treasury liquidity

### Notes

Do not expand adapter count unless the first adapter is fully convincing.

---

## Phase 4 — Treasury Operations And Automation

### Goals

- implement the core Treasury Operations Engine
- monitor treasury conditions
- produce bounded treasury actions
- make automation legible and controllable

### Deliverables

- treasury threshold monitoring
- surplus detection
- buffer deficit detection
- paused-state handling
- automated or auto-prepared low-risk action flow
- operations view in the dashboard
- Spectrum-backed live reads for automation checks and transaction execution

### Required V1 automated behaviors

- detect idle MUSD above threshold
- detect operating buffer shortfall
- block non-compliant allocation attempts
- propose or perform approved low-risk actions

### Success criteria

- TreasuryOS can show one real automated treasury response
- operators can understand why an action was allowed, blocked, or triggered
- the automation flow is clearly shown as running on top of Spectrum-backed Mezo testnet infrastructure

### Notes

If AI is used, it should support explanation and summarization only.
Do not make AI the controlling authority for treasury actions.

---

## Phase 5 — Treasury Reporting And Reviewer Views

### Goals

- make TreasuryOS feel like treasury software rather than protocol UI
- provide useful reporting for operators and reviewers

### Deliverables

- treasury activity timeline
- idle vs allocated summary
- destination exposure summary
- policy decision log
- reviewer-facing treasury summary
- documentation showing where Spectrum Nodes is used in the product architecture

### Success criteria

- a finance or reviewer stakeholder can understand what happened without reading raw transactions
- reporting reflects real state changes and policy outcomes

---

## Phase 6 — Demo Hardening

### Goals

- connect the workflow into one coherent demo
- remove weak transitions or mock-looking gaps
- harden failure paths and narrative clarity

### Deliverables

- final end-to-end scenario
- demo script
- fallback plan for live demo risk
- polished judge-facing narrative
- explicit Spectrum Nodes integration callout in the demo and architecture notes

### Required demo sequence

1. create Treasury Account
2. configure treasury policy and approvals
3. deposit BTC and borrow through TreasuryOS
4. receive MUSD into Treasury Account
5. keep required buffer and allocate surplus
6. trigger stress or liquidity condition
7. show automated or proposed response
8. show reporting and reviewer summary

### Success criteria

- the product looks like a workflow, not a set of disconnected features
- the institutional story is visible without overclaiming
- the product clearly fits the treasury management subtrack
- the Spectrum integration looks native to the product rather than bolted on for a side prize

---

## Must-Have V1 Scope

- Treasury Account deployment
- Treasury Policy Engine with core policies
- Mezo borrow origination inside TreasuryOS
- one Mezo-native allocation adapter
- bounded automated treasury operations
- reporting and reviewer surface
- clear demo narrative

---

## Should-Have V1 Scope

- multisig-aware approval flow
- one recovery or unwind path
- richer action explanations
- exportable reviewer summary artifact

---

## Optional V1 Scope

- second approved destination
- deeper signer integration
- AI-assisted narrative summaries

These are optional only if they do not weaken the product spine.

---

## Out-Of-Scope For V1

- proprietary TreasuryOS yield strategies
- broad destination marketplace
- full custody backend matrix
- ERP-grade accounting integrations
- cross-chain treasury orchestration
- autonomous AI treasury management
- large institutional workflow matrix beyond the core treasury flow

---

## Main Risk To Watch

The biggest roadmap risk is false breadth:

- too many integrations
- too many architectural modules
- too many automation claims
- too many institutional features at shallow depth

The build should stay focused on making one treasury workflow feel operationally real.

---

## Final Roadmap Standard

If the team finishes V1 and can honestly show:

- real Mezo borrow origination
- real treasury controls
- real governed allocation
- real bounded automation
- real reporting

then TreasuryOS will look materially stronger than a polished dashboard or generic vault wrapper.
