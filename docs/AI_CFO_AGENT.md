# AI-CFO Agent

TreasuryOS can support an AI-CFO model without trusting AI with treasury funds.

The product thesis is:

> The AI is an analyst and proposal writer. TreasuryOS policy is the control layer. Multisig and bounded keepers are
> the execution layer.

This gives small teams, DAOs, and BTC-heavy companies a treasury operator experience without hiring a full DeFi-native
finance team, while keeping institutional guardrails intact.

## What The AI-CFO Does

The AI-CFO monitors the treasury and prepares recommendations:

- reads TreasuryAccount state, BTC collateral, MUSD debt, idle MUSD, sleeve allocations, and reserve buckets
- reads live Mezo opportunities such as MUSD Savings, Tigris MUSD/mUSDC, and BTC-correlated candidates
- applies the selected treasury profile: `conservative`, `balanced`, `active`, or `aggressive-demo`
- ranks opportunities by policy fit, liquidity, route health, risk class, approval requirement, and execution readiness
- explains why an opportunity is recommended, optional, blocked, or proposal-only
- writes investment committee / treasury admin memos
- prepares multisig-ready proposal details for approved actions
- recommends keeper-safe defensive actions when risk changes
- produces post-action reporting and next-step review notes

## What It Must Not Do

The AI-CFO must not:

- hold private keys
- custody BTC, MUSD, receipt tokens, or LP tokens
- execute arbitrary swaps or allocations
- bypass `TreasuryPolicyEngine`
- move BTC principal without owner or multisig approval
- treat unvalidated testnet liquidity as production-safe yield
- charge fees on emergency defense actions

## Production Control Model

Production execution should use a Safe-like control pattern:

1. **AI-CFO analysis**
   - Reads state and opportunities.
   - Produces a recommendation, memo, and proposed calldata.

2. **Deterministic validation**
   - TreasuryOS advisor and keeper logic validate the recommendation against deterministic rules.
   - Onchain policy remains the source of truth for execution.

3. **Human or policy approval**
   - Treasury admin, Safe, TreasuryMultisig, or external custody flow approves sensitive actions.
   - Spending limits and approval thresholds define what can be routine versus elevated.

4. **Bounded execution**
   - Owner/multisig executes treasury actions.
   - Keeper can execute only whitelisted defensive actions through `TreasuryAutomationExecutor`.
   - Keeper EOA pays gas only and never receives treasury assets.

5. **Post-action reporting**
   - Snapshot verifies actual balances and positions.
   - AI-CFO writes a post-action memo from observed state.

## V1 Implementation Status

Implemented today:

- deterministic treasury advisor
- profile-aware opportunity review
- live Mezo opportunity reads for MUSD Savings, Tigris MUSD/mUSDC, and mcbBTC/BTC
- AI-CFO proposal packet with recommendation id, prepared action details, calldata helper, and blocked-opportunity reasons
- optional OpenAI-written memo over deterministic facts
- Treasury Risk Keeper dry-run, propose, and guarded execute mode
- live keeper execution proofs for buffer restoration and idle-MUSD debt repayment
- multisig-owned client TreasuryAccount
- policy-controlled MUSD Savings allocation

Current V1 boundary:

- AI/advisor does not execute transactions.
- AI memo is not the source of truth.
- Deterministic advisor output and onchain policy are the source of truth.
- Prepared actions are proposal artifacts, not broadcasts.
- BTC sleeve execution is not part of the main live demo until validation is complete.

## Recommended Product Flow

Pre-action:

1. Client selects profile.
2. AI-CFO reads treasury state and live Mezo opportunities.
3. Deterministic advisor ranks actions.
4. AI-CFO prepares a recommendation packet with proposal details and blocked-opportunity reasons.
5. AI-CFO writes a memo explaining the recommendation.
6. Treasury admin reviews proposal.

Execution:

1. Multisig executes approved allocation or treasury action.
2. Keeper executes only allowed defensive workflows if configured.

Post-action:

1. TreasuryOS refreshes snapshot.
2. AI-CFO explains what changed.
3. Reporting timeline records action, policy result, and new position state.

## Near-Term Roadmap

V1.1:

- add `advisor:plan` command for pre-action what-if planning before funds move
- add profile preset renderer that maps `TREASURY_PROFILE` into onboarding policy env values
- add memo hash or recommendation id to proposal artifacts for auditability

V1.5:

- Safe module / Safe transaction builder export
- EIP-712 signed recommendation intents
- per-client agent registry with allowed agent roles
- spending-limit configuration for routine MUSD allocations
- AI-CFO post-action reporting indexed through Goldsky

V2:

- MEZO-staked keeper/agent operators
- governance-approved public strategy templates
- paid AI/API/reporting credits
- more Mezo-native yield integrations after route and liquidity validation

## Demo Narrative

For the hackathon, describe it honestly:

> TreasuryOS is an AI-CFO for BTC treasuries on Mezo. The AI reads state, studies live opportunities, and writes the
> memo. Smart contracts enforce policy. Multisig and bounded keepers execute. The agent is not trusted; the policy is.
