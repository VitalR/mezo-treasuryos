# Term Yield Planner

The Term Yield Planner is a deterministic reporting service for 7/30/60-day treasury allocation planning.

It does not create a fixed-yield protocol, sign transactions, or move funds. It consumes the same treasury snapshot style used by the Yield Console and Advisor, then produces planning windows for approved MUSD sleeves.

Run:

```sh
npm run demo:term-planner
npm run planner:test
```

Planning rules:

- only MUSD surplus above the operating buffer is considered
- planned operating disbursements and extra reserve constraints reduce allocatable MUSD
- collateral warning or critical state blocks new term allocation
- each sleeve must be approved, have remaining cap, and be unwindable inside the selected window
- BTC sleeve candidates are reported as notes only unless a verified BTC execution path exists

The planner is intended for reviewer-facing treasury memos and investment committee style planning, not autonomous execution.
