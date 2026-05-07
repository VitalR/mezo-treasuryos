# BTC Reserve And Yield Sleeves

## Product Boundary

TreasuryOS should manage two related but separate treasury balance sheets:

- **MUSD operating capital:** borrowed working capital that must preserve a liquid MUSD operating buffer before allocation.
- **BTC-denominated treasury exposure:** idle BTC reserve, BTC collateral, and future BTC-correlated yield positions.

These should not share the same accounting path. V1 MUSD sleeves are policy-governed destinations for surplus MUSD. BTC sleeves need a separate BTC-principal policy and reporting model before they can become executable.

The product line is:

**TreasuryOS is not a wrapper around yield protocols. It is the institutional treasury operating layer that decides, controls, accounts for, automates, and reports how BTC treasury capital is deployed.**

## Current Mezo Surface

Current Mezo documentation gives us enough to support V1 MUSD/stable allocation and BTC reserve reporting:

- Mezo Testnet is EVM-compatible, uses chain ID `31611`, and uses BTC as the native gas currency.
- MUSD is the Bitcoin-backed stablecoin borrowed against BTC collateral.
- Tigris basic pools include MUSD/BTC, MUSD/mUSDC, and MUSD/mUSDT.
- Tigris concentrated liquidity includes BTC/MUSD.
- Mezo token references include several BTC-correlated bridged assets on mainnet-style docs, including BTC/tBTC and wrapped BTC variants.

Live testnet inspection of the Tigris basic pools shows `MUSD/mUSDC` as a stable pool and `MUSD/BTC` as a non-stable pool paired with the ERC-20 BTC token at `0x7b7C000000000000000000000000000000000000`. That is useful for a future directional BTC/stable sleeve, but it is not the same as native BTC reserve yield.

What is not yet clean enough for TreasuryOS V1:

- a verified BTC/wrapperBTC testnet pool target with the exact handler requirements;
- a production-style native BTC wrap/swap path suitable for account-owned treasury automation;
- a BTC-principal policy engine that accounts for idle BTC, collateral BTC, wrapper BTC, and LP receipt BTC exposure in one enforceable model.

Because of that, V1 should not ship a `BTCReserveRouter` or `TigrisBTCPoolHandler` as executable capital movement unless the handler is wired to a verified Mezo testnet target and tested end to end.

## V1 Scope

V1 should implement:

- MUSD Savings Rate as the primary reliable MUSD sleeve.
- Tigris MUSD/mUSDC stable pool as the secondary MUSD sleeve, with slippage and min-out protection.
- Treasury reporting that distinguishes:
  - idle MUSD;
  - required MUSD buffer;
  - allocatable MUSD surplus;
  - MUSD sleeve exposure;
  - idle BTC reserve;
  - BTC collateral;
  - BTC sleeve candidates and whether they are executable.
- AI/advisor memo language that explains BTC reserve and BTC collateral separately from MUSD surplus.

V1 may show BTC sleeve candidates in the reporting layer, but they must be explicitly marked as research or planning-only unless the execution path is live.

## BTC Sleeve Classification

### BTC/wrapperBTC or BTC-correlated sleeve

This is the cleanest Bitcoin-yield direction because it can preserve BTC-denominated exposure better than a BTC/stable LP.

V1 status: design and reporting candidate only unless a verified Mezo/Tigris target exists.

Future handler requirements:

- accept native BTC or a BTC-correlated ERC-20 asset;
- optionally wrap native BTC into the required pool asset;
- deposit into a BTC-correlated sleeve;
- withdraw back to native BTC or a BTC-correlated ERC-20;
- report principal asset, receipt asset, allocated BTC, claimable rewards, lock/withdrawal constraints, and BTC-equivalent exposure.

### MUSD/BTC or BTC/stable LP

This is a directional treasury strategy, not a pure BTC reserve yield sleeve.

It may make sense for a treasury that intentionally wants:

- partial stablecoin exposure;
- LP fee exposure;
- potential BTC accumulation if BTC price drops;
- reduced pure BTC upside in exchange for LP economics.

V1 status: planning-only unless elevated approval and separate BTC/MUSD accounting are added.

### veBTC and production BTC yield surfaces

This belongs in V2 unless the contract interface, lock behavior, rewards, and withdrawal constraints are fully understood and tested.

V1 should mention this as future Mezo-native BTC treasury work, not a shipped V1 execution path.

## Naming Recommendation

Avoid calling the future module generic "native" because BTC is already the native gas token on Mezo EVM.

Preferred names:

- `BTCReserveAllocationRouter`
- `BTCReserveSleeveRouter`
- `BTCReservePolicy`
- `BTCYieldPositionRegistry`

For V1 docs, use "BTC reserve and BTC-denominated sleeves" rather than naming a contract that does not exist yet.

## Future Onchain Shape

Add executable BTC sleeves only when there is a real target and a separate accounting path.

Minimal future components:

- `IBTCReserveSleeveHandler`
- `BTCReservePolicy`
- `BTCReserveAllocationRouter`
- `BTCYieldPositionRegistry`

Minimal handler interface:

- deposit native BTC or approved BTC-correlated asset;
- withdraw;
- claim rewards if supported;
- preview BTC-equivalent exposure;
- report principal asset, receipt asset, receipt balance, allocated BTC, claimable rewards, lock duration, withdrawal delay, and risk class.

Minimal policy checks:

- keep minimum idle BTC reserve;
- do not touch BTC collateral needed for position health;
- cap each BTC sleeve in BTC terms;
- require elevated approval for BTC/stable LP;
- block automation when collateral health weakens;
- treat long-lock sleeves as proposal-only.

## Roadmap Classification

### V1

- MUSD Savings Rate handler.
- Tigris MUSD/mUSDC handler with min-out/slippage controls.
- BTC reserve and collateral fields in reporting/advisor output.
- BTC sleeve candidates marked as research, reporting-only, or execution-ready.
- AI memo that distinguishes MUSD operating capital from BTC reserve/collateral.

### V1.5

- `BTCReservePolicy`.
- BTC treasury risk profiles.
- BTC yield intents that create multisig proposals rather than direct autonomous execution.
- BTC/stable LP classification and elevated approval rules.
- BTC-denominated exposure and PnL reporting.

### V2

- BTC-correlated executable sleeve router.
- veBTC or Enclave-accessible BTC yield integration if available.
- BTC lock-duration and withdrawal-delay aware automation.
- richer investment committee reporting.
- multi-sleeve BTC allocation strategy.
