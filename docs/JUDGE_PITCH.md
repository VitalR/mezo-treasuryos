# Mezo TreasuryOS — Judge Pitch

## One-Line Pitch

**Mezo TreasuryOS turns Mezo's BTC-backed MUSD borrowing into a governed treasury workflow with isolated treasury accounts, policy controls, approved allocation routing, automated operations, and reporting.**

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
- governed allocation routing into approved Mezo-native sleeves
- bounded automated treasury operations
- treasury reporting and reviewer visibility

For the hackathon build, TreasuryOS uses **Spectrum Nodes** as the primary Mezo testnet RPC provider for treasury state reads, monitoring, and transaction execution.

TreasuryOS is Spectrum-preferred rather than Spectrum-assumed: the demo runs `make rpc-health`, tests multiple configured Spectrum Mezo Testnet RPC candidates for chain ID `31611`, uses Spectrum when healthy, and falls back to official Mezo RPC only for reliability if no Spectrum candidate is active.

Goldsky is the planned reporting indexer for treasury activity timelines, sleeve exposure history, automation events, and multisig approval history. The V1 scaffold indexes real TreasuryOS events only and stays paired with live Spectrum-backed snapshots for current balances and policy previews.

---

## How It Works

1. A treasury creates a Treasury Account in TreasuryOS.
2. The treasury configures roles, approvals, liquidity buffer, and allowed sleeves.
3. The treasury deposits BTC and opens a Mezo-backed MUSD position through TreasuryOS.
4. Minted MUSD lands directly into the Treasury Account.
5. TreasuryOS keeps the required operating buffer liquid.
6. Treasury can disburse idle MUSD for real operating use under policy.
7. Only surplus MUSD can be allocated into approved Mezo-native sleeves.
8. TreasuryOS monitors treasury conditions and proposes or executes bounded actions.
9. TreasuryOS produces reviewer-ready reporting and action logs.

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
- router-based multi-sleeve allocation
- BTC reserve and collateral reporting separate from MUSD operating capital
- one automated treasury response flow
- one reviewer-facing treasury report

Current V1 sleeves:

- **MUSD Savings Vault** at `0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`
- **Tigris Basic Stable `MUSD/mUSDC` pool** at `0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`

That keeps V1 additive to Mezo while still showing more than a single passive vault path.
The contract setup is sleeve-extensible for future MUSD-denominated Mezo-native destinations: a client admin can register a new handler and update destination approval/cap policy without redeploying the Treasury Account.

For demo reliability, MUSD Savings Vault remains the primary allocation sleeve. Tigris `MUSD/mUSDC` is a secondary sleeve that strengthens differentiation when testnet liquidity is healthy; if pool liquidity is poor, TreasuryOS can still prove the full governed treasury workflow with savings allocation and buffer restoration. The real Tigris `mcbBTC/BTC` stable pool is reported as the BTC-correlated yield candidate, not routed through MUSD accounting.

The yield angle is intentionally treasury-native:

- preserve the operating buffer first
- allocate only surplus MUSD
- enforce approved sleeves and caps
- preview why an allocation is allowed or blocked
- report BTC reserve and BTC collateral separately from borrowed MUSD
- treat BTC/stable LP as a directional planning candidate, not default treasury yield
- generate an AI-assisted treasury memo that remains advisory

---

## Automation Story

TreasuryOS includes automated treasury operations, but in a bounded and explainable way.

Examples:

- sweep excess idle MUSD into an approved sleeve
- withdraw from a sleeve to restore operating buffer
- disburse idle MUSD for treasury operations under policy
- block actions that violate treasury policy
- pause allocation under stress or policy changes
- generate clear action summaries for operators and reviewers

This is treasury automation, not black-box AI capital management.

## AI Story

AI is not the signer, policy engine, or executor.

AI reads TreasuryOS state and generates an allocation memo:

- current BTC-backed MUSD position
- idle versus allocated MUSD
- idle BTC reserve and BTC collateral
- BTC-denominated sleeve candidates and whether they are execution-ready or planning-only
- allocatable surplus above buffer
- sleeve exposure and cap pressure
- policy decisions and blocked actions
- collateral-health notes
- recommended next treasury step

That makes TreasuryOS feel like an operations product without weakening onchain controls.

---

## Demo Story

The strongest demo is:

1. Create a Treasury Account
2. Configure policy and approvals
3. Deposit BTC and borrow MUSD through TreasuryOS
4. Show MUSD arriving into the Treasury Account
5. Disburse a portion for treasury operating use
6. Keep an operating buffer and allocate only surplus MUSD into approved sleeves
7. Trigger a stress or liquidity event
8. Show TreasuryOS restoring buffer or blocking a risky action
9. Show the Treasury Yield Console and AI memo explaining what happened and why

Throughout the flow, show the selected Mezo testnet RPC provider. If `make rpc-health` selects Spectrum, call out that live reads, monitoring, and transaction execution are running through **Spectrum Nodes**; if not, show the official fallback honestly and keep Spectrum as the preferred provider path.

If that flow works, TreasuryOS feels like a product, not a prototype.

---

## Final Judge Takeaway

**TreasuryOS makes Mezo's BTC-backed liquidity usable as governed treasury capital.**

It gives Mezo a product layer for treasury controls, approvals, allocation, automation, and reporting, which is exactly what serious BTC treasury users need beyond raw borrow access.
