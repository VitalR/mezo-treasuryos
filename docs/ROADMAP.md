# Mezo TreasuryOS — Roadmap

## Purpose

This roadmap defines the build sequence for **Mezo TreasuryOS V1** under the current product direction.

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
6. disburse operating MUSD where needed
7. allocate approved surplus MUSD into approved Mezo-native sleeves
8. trigger a stress or liquidity condition
9. show a bounded automated treasury response
10. produce reviewer-facing reporting

If that workflow works end to end, the build is successful.

---

## Build Strategy

The roadmap should follow one rule:

**build the product spine first**

The product spine is:

- Treasury Account
- Treasury Account-owned Mezo position lifecycle
- Treasury Policy Engine
- one allocation router
- two sleeve handlers
- one automation loop
- one reporting loop

Anything that does not strengthen that spine should be deferred.

---

## Phase 0 — Product Lock And Reference Validation

### Goals

- lock the product thesis
- lock the V1 workflow
- lock naming and positioning
- confirm the Mezo integration surfaces to use
- lock the primary Mezo testnet RPC provider
- lock the approved Mezo testnet sleeve set
- reduce ambiguity before implementation starts

### Deliverables

- `PRODUCT_VISION.md`
- `PROJECT_SPEC.md`
- `ARCHITECTURE.md`
- `JUDGE_PITCH.md`
- confirmed integration assumptions for Mezo borrow and sleeve destinations
- Spectrum Nodes selected and documented as the primary Mezo testnet RPC provider
- Tigris testnet sleeve targets identified and documented

### Success criteria

- the team can explain the product in one clear sentence
- the V1 workflow is concrete and stable
- the sleeve set is locked
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
  - allowed sleeve policy
  - allocation cap policy

---

## Phase 2 — Borrow Origination Through TreasuryOS

### Goals

- integrate Mezo-native BTC-backed borrow flow into TreasuryOS
- make TreasuryOS the product entry point for treasury origination
- ensure Treasury Account owns the position lifecycle and borrowed MUSD
- wire Spectrum Nodes into testnet reads and transaction broadcasting for this flow

### Deliverables

- Treasury Account position lifecycle methods
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
If borrow origination or position ownership is weak or fake, the whole product becomes a post-draw shell again.

---

## Phase 3 — Governed Allocation Layer

### Goals

- add one real router-based allocation layer
- enforce buffer and sleeve rules on allocation
- support deposit, withdrawal, and operating disbursement flows

### Deliverables

- `AllocationRouter`
- `MUSDSavingsRateHandler`
- `TigrisStablePoolHandler`
- destination state tracking
- governed allocation UI flow
- integration tests for deploy and withdraw behavior
- Spectrum-backed polling for sleeve and treasury balance state

### Current V1 sleeves

- **MUSD Savings Rate**
- **Tigris `MUSD/mUSDC` stable pool on Mezo testnet**

### Success criteria

- only permitted surplus MUSD can be allocated
- allocation cap rules are enforced
- the product can withdraw from sleeves to restore treasury liquidity
- the Treasury Account can disburse idle MUSD for operations under policy

### Notes

Do not expand beyond the current sleeve set unless both sleeves are fully convincing.

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
- block non-compliant operating disbursements
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
- sleeve exposure summary
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
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into Treasury Account
5. disburse a portion for treasury operations
6. allocate approved surplus into savings and approved Tigris sleeve
7. trigger buffer or policy condition
8. show bounded treasury response
9. show reporting and reviewer view
10. explicitly show Spectrum Nodes in the stack narrative
