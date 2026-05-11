# Protocol Fees

TreasuryOS should monetize like institutional treasury software, not like an extractive DeFi router.

The V1 fee architecture is intentionally narrow:

- fees default to zero
- fee quoting and explicit subscription payments are disabled by default
- emergency defense actions are never fee-charged
- BTC and MUSD principal is not skimmed
- fee funds route to `ProtocolFeeVault`, not an EOA
- governance/admin control is bounded by hard caps
- ERC20 subscription tokens are governance-allowlisted

For the hackathon demo, the correct position is: fee contracts may be deployed and recorded in the manifest, but protocol fees are disabled.

## Recommended Model

Primary revenue should be a subscription or service fee for:

- treasury monitoring
- collateral and liquidity reporting
- keeper automation support
- AI advisor memos and operating recommendations
- audit/export workflows

MUSD is the preferred subscription payment token because it gives institutions clean stablecoin accounting. Native BTC can be supported for BTC-native clients, but it should be explicit and never pulled from collateral or reserve principal.

Secondary revenue can be a small performance fee on realized positive yield. It should apply only when a yield or optimization path returns more than the deployed principal. There is no fee on breakeven outcomes or losses.

Optional later revenue:

- setup or onboarding fee for enterprise deployment
- paid API/report generation
- paid AI memo generation

Avoid per-emergency-action fees. TreasuryOS should not look like it profits when a client is under liquidation stress.

## Current Implementation

`ProtocolFeeVault` is the protocol fee receiver.

- uses `Ownable2Step`
- receives native BTC
- accepts structured native BTC deposits through `depositNative`
- accepts ERC20 deposits through `depositERC20`
- lets the owner withdraw native BTC or ERC20 fees
- rejects withdrawal recipients that are not contracts, so fee custody does not resolve to a bare EOA
- emits fee receive and withdrawal events

`ProtocolFeeManager` stores fee configuration and fee quotes.

- uses `Ownable2Step`
- requires a contract `feeVault`
- has a global `feesEnabled` switch
- defaults all fee rates to zero and disabled
- caps performance fee at `300 bps`
- caps origination fee at `25 bps`
- caps optimization action fee at `5 bps`
- quotes performance fees only on realized positive yield
- allowlists ERC20 subscription payment tokens through `setAcceptedSubscriptionToken`
- includes explicit ERC20 `paySubscription` support routed to the fee vault
- includes explicit native BTC `payNativeSubscription` support routed to the fee vault

The subscription functions are implemented now because they are simple, explicit, and do not touch treasury principal. They are gated by `feesEnabled`, so they cannot collect during the zero-fee demo unless governance deliberately enables the fee config. ERC20 subscriptions also require the payment token to be explicitly accepted by governance.

## Event Indexing

Subscription payments and direct vault deposits intentionally use different event sources.

Index subscription/service payments from `ProtocolFeeManager`:

- `SubscriptionPaid` for ERC20 subscriptions
- `NativeSubscriptionPaid` for native BTC subscriptions

Index direct vault deposits from `ProtocolFeeVault`:

- `FeeReceived` from `depositNative`
- `FeeReceived` from `depositERC20`

`ProtocolFeeVault.FeeReceived` is not emitted for subscription payments routed through `ProtocolFeeManager`. This prevents indexers from double-classifying a manager subscription as both a subscription and a direct vault deposit.

## Not Implemented In V1

The fee manager is not wired into:

- `TreasuryAccount.openTrove`
- debt repayment
- collateral top-up
- liquidity buffer restoration
- emergency defense automation
- BTC reserve sleeve principal movement
- MUSD sleeve deposit/withdraw principal accounting

This is deliberate. The deployment can prove a clean monetization architecture without changing the risk posture of the live demo.

## Fee Policy

Performance fee:

- default: `0 bps`
- hard cap: `300 bps`
- charged only on `returnedAmount - principal`
- zero when fees are disabled
- zero when `returnedAmount <= principal`

Origination fee:

- default: `0 bps`
- hard cap: `25 bps`
- not wired into borrowing for the hackathon demo
- should remain opt-in and clearly disclosed if introduced later

Optimization action fee:

- default: `0 bps`
- hard cap: `5 bps`
- not wired into emergency defense
- suitable only for explicit non-emergency optimization workflows if used later

Emergency defense fee:

- always `0`
- no liquidation-defense keeper fee
- no fee on buffer restore
- no fee on idle-MUSD debt repayment
- no fee on idle-BTC collateral top-up

## MEZO Utility Options

MEZO should be treated as a product utility surface, not a hidden fee path.

Possible future uses:

- pay subscription in MEZO for a discount
- MEZO holdings or staking unlock premium analytics
- MEZO credits for AI advisor calls, API calls, or report generation
- MEZO-staked keeper operators in V2
- MEZO governance over public strategy templates later

None of these are required for the V1 deployment.

## x402 And API Payments

x402-style payments can fit later for narrow, stateless service calls:

- AI memo generation
- downloadable reports
- API snapshots
- strategy-template simulations

x402 should not gate core custody, collateral defense, debt repayment, or emergency execution.

## Deployment Posture

If deployed, manifests should record:

- `protocolFeeVault`
- `protocolFeeManager`

The final demo should state:

- fee contracts are deployed for governance-ready architecture
- all fee rates are zero by default
- `feesEnabled` is false by default
- ERC20 subscription token allowlists are governance-controlled
- no principal-skimming hooks are active
- emergency defense actions are not fee-charged
