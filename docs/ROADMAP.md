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
2. configure treasury owner, roles, and policy settings
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into the Treasury Account
5. preserve a configured operating buffer
6. disburse operating MUSD through the required treasury control path
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
- optional TreasuryMultisig or external multisig/custody owner
- one allocation router
- two sleeve handlers
- one automation loop
- one reporting loop

Anything that does not strengthen that spine should be deferred.

## Yield And Investment Angle

The yield angle belongs inside the treasury workflow, not beside it as a separate product.

V1 should add:

- policy-governed yield allocation of surplus MUSD only
- a Treasury Yield Console that shows idle MUSD, required buffer, allocatable surplus, approved sleeves, caps, exposure, and the policy decision for a proposed allocation
- an AI-CFO advisory layer that reads state and live Mezo opportunities, ranks policy-aware actions, writes memos, and prepares proposals while never controlling funds
- a lightweight Term Yield Planner for 7/30/60-day treasury planning, using projected assumptions, review dates, buffer constraints, and unwind conditions
- BTC reserve and collateral reporting that distinguishes retained BTC-denominated exposure from borrowed MUSD operating capital
- BTC-denominated sleeve candidates marked as planning-only unless a separate BTC accounting/policy path and verified handler target exist
- liquidation-defense policy and keeper output so TreasuryOS can block unsafe borrow/allocation structures and defend positions before yield routing

V1 should not build:

- a proprietary high-yield vault
- a general strategy marketplace
- a Pendle-style fixed-yield protocol
- autonomous AI execution
- executable BTC-principal allocation through the MUSD `AllocationRouter`

The right posture is: TreasuryOS helps a treasury decide, approve, execute, and explain approved Mezo-native allocation of surplus MUSD, while accounting for BTC reserve and BTC collateral separately.

The AI-CFO posture is deliberately constrained: AI can monitor, explain, rank, and draft proposals. `TreasuryPolicyEngine`,
`TreasuryMultisig`, and `TreasuryAutomationExecutor` define what can actually execute.

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
- Spectrum Nodes selected and documented as the primary Mezo testnet RPC provider, with multi-endpoint health checks and official Mezo RPC fallback if no Spectrum candidate answers as Mezo EVM testnet
- Goldsky indexing scaffold for treasury activity and reporting
- Tigris testnet sleeve targets identified and documented

### Success criteria

- the team can explain the product in one clear sentence
- the V1 workflow is concrete and stable
- the sleeve set is locked
- the RPC decision is locked early enough to shape the monitoring and demo stack
- `make rpc-health` selects Spectrum when a configured Spectrum endpoint returns chain ID `31611`, otherwise falls back honestly
- the product is clearly differentiated from Mezo Institutional without retreating from the subtrack

---

## Phase 1 — Treasury Control Foundation

### Goals

- implement client-isolated Treasury Account deployment
- implement the initial Treasury Policy Engine
- define roles, approvals, and treasury action boundaries
- add multisig-compatible Treasury Account ownership for critical treasury actions
- establish event model for state and reporting
- prepare the event and read model for Spectrum-backed treasury state services

### Deliverables

- `TreasuryAccountFactory`
- `TreasuryAccount`
- initial `TreasuryPolicyEngine`
- `TreasuryMultisig` for optional onboarding/demo treasury control
- unit tests for account isolation and policy enforcement
- unit tests proving multisig-controlled setup and business MUSD disbursement
- treasury event schema
- RPC and event-read assumptions documented for Spectrum-backed state consumption

### Success criteria

- a new treasury can deploy an isolated Treasury Account
- basic treasury roles and permissions are enforceable
- critical setup and elevated operating withdrawals can be executed by a multisig/custody owner
- bounded automation remains separate from multisig-controlled business withdrawals
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
- treasury-controlled open and adjust actions are checked against configured projected collateral-ratio and stress policy
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
- `BTCReservePolicy`
- destination state tracking
- admin-governed destination policy updates for adding or recapping future MUSD-denominated sleeves without redeploying Treasury Accounts
- allocation decision preview for proposed sleeve actions
- BTC-denominated reserve bucket accounting and preview-only BTC sleeve policy
- governed allocation UI flow
- integration tests for deploy and withdraw behavior
- Spectrum-backed polling for sleeve and treasury balance state

### Current V1 sleeves

- **MUSD Savings Vault** at `0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`
- **Tigris Basic Stable `MUSD/mUSDC` pool** at `0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`
- **Tigris Basic Stable `mcbBTC/BTC` pool** at `0xc8BA1027e1D4f9C646B9963Eab89B1e7CF2A476E` as a BTC-correlated reporting/scaffold candidate

### Success criteria

- only permitted surplus MUSD can be allocated
- allocation cap rules are enforced
- the product can withdraw from sleeves to restore treasury liquidity
- the Treasury Account can disburse idle MUSD for operations under policy, with elevated withdrawals controlled by the treasury admin path
- reviewers can see why a proposed allocation is allowed or blocked before execution

### Notes

Do not expand the executable MUSD sleeve set beyond MUSD Savings Vault and MUSD/mUSDC unless both are fully convincing. Keep mcbBTC/BTC as BTC-correlated reporting/scaffold or experimental preview until BTC execution is transaction-tested through a guarded handler.

The contract spine can add another MUSD-denominated sleeve later through router handler registration plus destination policy/cap updates. Do not describe this as native BTC-principal allocation support until separate BTC sleeve accounting exists.

Tigris `mcbBTC/BTC` is the cleanest current BTC-correlated yield candidate because it preserves BTC-like exposure better than BTC/stable LP. Manual Mezo testnet transaction inspection confirms the UI path uses ERC20-style BTC at the BTCCaller/precompile address, so the old "native BTC mechanics unknown" blocker is reduced. V1 now supports proposal-only BTC sleeve planning from idle BTC reserve using pool reserves, a BTC -> mcbBTC quote, min-out/min-LP calculations, and BTCReservePolicy guardrails. V1.5 adds `BTCReserveRouter` and `TigrisBTCStablePoolHandler` for guarded owner/multisig execution with swap min-out, LP min-liquidity, BTC-principal accounting, price-impact/slippage policy, and separate BTC handler authorization. Tigris `MUSD/BTC` and BTC/MUSD concentrated liquidity should be treated as directional BTC/stable strategies, not as the default BTC treasury yield story.

V1 BTC sleeve scope is deliberately a calculator plus policy gate plus advisor memo. It should show MUSD Savings execution, optional MUSD/mUSDC execution, and a BTC sleeve planner that blocks mcbBTC/BTC when price impact, reserve floors, or approval level fails policy. V1.5 guarded execution is implemented as a narrow contract path, but the final demo should not rely on it until controlled testnet broadcast validation passes. The next validation item is `make btc-sleeve-broadcast-dry-run`, followed by `make btc-sleeve-broadcast-validation` only with `BTC_SLEEVE_BROADCAST_CONFIRM=true` in `.env`. LP stake/unstake and reward claim remain separate after deposit/unwind is stable.

For the final demo, keep **MUSD Savings Vault** as the primary guaranteed allocation sleeve. Tigris `MUSD/mUSDC` now has a passing live-fork TreasuryOS deposit/withdraw simulation, but it remains the secondary differentiating sleeve because current testnet liquidity can be thin or imbalanced. Re-run `make demo-status`, `make yield-targets`, and `make mezo-yield-fork-test` before the demo. If Tigris liquidity is poor or the route is unstable, the demo should still show the full treasury workflow through savings: surplus calculation, policy approval, allocation, buffer restoration, automation, reporting, and advisory memo.

Before Tigris is used in the final demo allocation path, keep slippage/min-out controls enabled in `TigrisStablePoolHandler`.
The required protection is standard AMM execution hygiene:

- minimum paired token output quoted from the router when swapping MUSD into the paired stable
- minimum token amounts used and minimum LP liquidity minted when adding stable-pool liquidity
- minimum token amounts returned when removing liquidity and minimum MUSD output when swapping paired tokens back

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
- policy-aware recommendation inputs for the AI memo layer
- Spectrum-backed live reads for automation checks and transaction execution
- strategy-aware Treasury Risk Keeper report for collateral health, post-stress CR, defense capacity, and recommended action
- direct idle-MUSD debt repayment through the automation executor, capped by policy
- idle BTC collateral top-up path for liquidation defense

### Required V1 automated behaviors

- detect idle MUSD above threshold
- detect operating buffer shortfall
- restore buffer from an approved sleeve within configured automation limits
- repay debt from idle MUSD within configured automation limits
- withdraw from an approved sleeve and repay debt within configured automation limits
- add accounted idle BTC to collateral within configured automation limits when that is the least disruptive defense action
- block non-compliant allocation attempts
- block non-compliant operating disbursements
- block unsafe borrow, debt-increase, collateral-withdrawal, and BTC-yield allocation structures when stress or reserve checks fail
- propose or perform approved low-risk actions

### Success criteria

- TreasuryOS can show one real automated treasury response
- final demo can show dry-run, proposal calldata, and guarded one-action execution for idle-MUSD repayment
- operators can understand why an action was allowed, blocked, or triggered
- the automation flow is clearly shown as running on top of Spectrum-backed Mezo testnet infrastructure

### Notes

AI should support analysis, explanation, proposal drafting, and post-action reporting. It may act like an AI-CFO for
small teams that lack a dedicated DeFi treasury operator, but it must not become the controlling authority for treasury
actions. Deterministic advisor logic and onchain policy remain the source of truth.

The keeper action model is strategy-aware, not a rigid ladder. Idle BTC collateral top-up may be preferred before unwinding MUSD Savings when the treasury explicitly reserves BTC for collateral defense. If idle BTC is scarce and MUSD Savings is immediately withdrawable, the keeper can prefer MUSD repayment. Offchain MUSD already disbursed for payroll, vendors, settlement, or business operations does not count as defense capacity unless explicitly imported.

---

## Phase 5 — Treasury Reporting And Reviewer Views

### Goals

- make TreasuryOS feel like treasury software rather than protocol UI
- provide useful reporting for operators and reviewers

### Deliverables

- treasury activity timeline
- idle vs allocated summary
- sleeve exposure summary
- BTC reserve, BTC collateral, and BTC sleeve-candidate summary
- policy decision log
- Goldsky-powered event history for account, policy, sleeve, automation, and multisig activity
- Treasury Yield Console
- AI Treasury Allocation Advisor memo output
- AI-CFO pre-action opportunity review over live Mezo opportunity reads
- Term Yield Planner view for simulated 7/30/60-day plans
- deterministic term-yield planner service for review dates, projected MUSD sleeve yield, and unwind conditions
- deterministic treasury advisor service that recommends sleeve allocation and bounded automation actions from snapshot inputs
- structured recommendation output for dashboard, API, and multisig proposal preparation
- BTC reserve strategy notes documenting V1/V1.5/V2 boundaries
- reviewer-facing treasury summary
- documentation showing where Spectrum Nodes is used in the product architecture

### Success criteria

- a finance or reviewer stakeholder can understand what happened without reading raw transactions
- reporting reflects real state changes and policy outcomes
- recommendations stay advisory and map back to policy state, buffer state, sleeve caps, exposure, and collateral health
- reporting does not imply that BTC-principal allocation is live unless a BTC handler has been implemented and deployed

### Notes

The AI layer should produce treasury memos such as:

- idle MUSD exceeds the buffer by a specific amount and only that surplus is allocatable
- a sleeve cap is close to full and another approved sleeve is preferred
- collateral health is weakening, so the next action should be buffer restoration or debt repayment rather than more allocation

The Term Yield Planner should remain reporting-oriented in V1. It can model allocation windows, projected yield assumptions, maturity/review dates, and unwind conditions without creating new fixed-yield instruments.

---

## AI-CFO / Agentic Treasury Roadmap

The valuable version of agentic treasury management is not a model that directly controls funds. It is an AI-CFO that
does the expensive operator work: monitoring, comparing opportunities, explaining tradeoffs, drafting proposals, and
producing reporting, while TreasuryOS contracts enforce the hard limits.

### V1 Scope

- deterministic advisor ranks opportunities from a treasury snapshot and live Mezo reads
- profiles map client intent into conservative, balanced, active, or aggressive-demo recommendations
- AI-CFO packet prepares recommendation id, proposed action details, calldata helper, and blocked-opportunity reasons
- optional OpenAI memo summarizes deterministic facts for treasury admins and judges
- keeper recommendations stay bounded to already-whitelisted defensive workflows
- no AI signer, no AI custody, no arbitrary agent swaps

### V1.1 Scope

- `advisor:plan` pre-action what-if command for onboarding and rebalancing proposals
- richer structured recommendation JSON with input sources, profile, proposed action, blocked actions, and policy reasons
- Safe/external custody proposal export that includes memo text, calldata, expected state change, and risk notes
- recommendation id or memo hash in proposal artifacts for auditability
- dashboard view that shows "Recommended / Optional / Blocked" opportunities before the user acts

### V1.5 Scope

- Safe transaction builder export or module integration
- EIP-712 signed recommendation intents from approved operators or agents
- per-client agent registry with monitor, proposer, reporter, and keeper roles
- explicit spending limits for routine MUSD allocations, separate from BTC principal movement
- Goldsky-indexed recommendation and execution timeline

### V2 Scope

- MEZO-staked keeper or agent operators
- governance-approved public strategy templates
- paid AI/API/reporting credits
- broader Mezo-native yield integrations after route, liquidity, and unwind validation

Production line to preserve:

> The AI-CFO can recommend and prepare. Policy, multisig, and bounded executors decide what can move.

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
- Goldsky indexing story with clear deployed-address/start-block prerequisites

### Required demo sequence

1. create Treasury Account
2. configure treasury policy and approvals
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into Treasury Account
5. disburse a portion for treasury operations
6. allocate approved surplus into savings and approved Tigris sleeve
7. trigger buffer or policy condition
8. show bounded treasury response
9. show Treasury Yield Console with policy decision result
10. show AI treasury memo and reviewer view
11. explicitly show the active RPC provider and Spectrum-preferred selection path
12. show the Goldsky-backed reporting/indexing plan without pretending unpublished indexer state is live
