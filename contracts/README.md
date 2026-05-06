# Mezo TreasuryOS Contracts

Foundry workspace for the TreasuryOS onchain layer.

## Contract Map

- `core/TreasuryAccountFactory.sol`: deploys and registers isolated Treasury Accounts.
- `core/TreasuryAccount.sol`: client treasury boundary that owns the Mezo position lifecycle, idle MUSD, and sleeve receipt assets.
- `core/TreasuryPolicyEngine.sol`: treasury roles, approvals, buffer, sleeve, cap, pause, and automation policy checks.
- `core/TreasuryAutomationExecutor.sol`: bounded automation executor for approved low-latency workflows.
- `multisig/TreasuryMultisig.sol`: optional TreasuryOS-native multisig controller for critical setup and elevated treasury actions.
- `adapters/AllocationRouter.sol`: maps approved destinations to sleeve handlers.
- `adapters/MUSDSavingsRateHandler.sol`: routes idle MUSD into a MUSD Savings Rate-compatible sleeve.
- `adapters/TigrisStablePoolHandler.sol`: routes approved MUSD into a Tigris stable-pool sleeve with min-out/min-liquidity protection.
- `external/ExternalMUSDSavingsRateMock.sol`: demo/test external savings surface with controlled yield funding.

## Control Model

Funds and Mezo position ownership stay in `TreasuryAccount`.

The Treasury Account owner is the treasury admin authority. It can be an external Safe/Den/Porto-style account, another contract wallet, or the optional `TreasuryMultisig`. Critical setup and elevated business MUSD disbursements should execute through that owner.

`TreasuryAutomationExecutor` is intentionally narrower. It can only trigger bounded workflows such as buffer restoration or sleeve-funded debt repayment after `TreasuryPolicyEngine` authorizes the executor and action limits.

`TreasuryAccount.previewAllocation(...)` exposes a read-only decision for treasury consoles and memo generation. Enforcement still lives in `TreasuryPolicyEngine`; the preview only explains the current policy result before execution.

## Commands

Run from the repository root:

```sh
make build
make test
make fmt
```

Or directly from this directory:

```sh
forge build
forge test --offline
forge fmt
```
