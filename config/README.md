# Config

This folder contains shared network configuration for **Mezo TreasuryOS**.

The current target is **Mezo Testnet**.

---

## Current Files

- `mezo-testnet.json` — checked-in network metadata and confirmed public contract addresses

Environment-specific secrets and RPC credentials should not be committed here. Use the root `.env` file derived from `.env.example`.

---

## Mezo Testnet Baseline

TreasuryOS currently assumes:

- network: **Mezo Testnet**
- chain ID: `31611`
- primary RPC provider: **Spectrum Nodes**

The checked-in config includes the currently confirmed public Mezo testnet addresses for:

- MUSD core borrow flow
- MUSD token
- Tigris router and pool factory
- Tigris `MUSD/mUSDC` stable pool

It intentionally does **not** hardcode an official Mezo testnet savings-vault address yet, because that address has not been pinned from an official public source in this repo workflow.

Until that address is confirmed, TreasuryOS should use one of these approaches:

- set `MEZO_MUSD_SAVINGS_RATE` in `.env` to the official testnet deployment once confirmed
- deploy `ExternalMUSDSavingsRateMock` for demo and local integration scenarios

---

## Required Runtime Variables

The root `.env.example` defines the shared runtime surface.

The most important variables are:

- `MEZO_RPC_URL`
- `MEZO_CHAIN_ID`
- `MEZO_MUSD_TOKEN`
- `MEZO_BORROWER_OPERATIONS`
- `MEZO_TROVE_MANAGER`
- `MEZO_HINT_HELPERS`
- `MEZO_SORTED_TROVES`
- `MEZO_PRICE_FEED`
- `MEZO_MUSD_SAVINGS_RATE`
- `MEZO_TIGRIS_ROUTER`
- `MEZO_TIGRIS_POOL_FACTORY`
- `MEZO_TIGRIS_MUSD_MUSDC_POOL`

TreasuryOS-specific deployment and scenario variables are also defined there for:

- deployer
- treasury owner
- treasury approver
- treasury operator
- automation service settings

---

## Source Of Truth

Use `mezo-testnet.json` as the checked-in baseline for public addresses.

Use `.env` for:

- RPC credentials
- private keys
- deployment overrides
- unresolved or environment-local addresses

If a checked-in config value and `.env` override disagree, runtime should prefer `.env`.

---

## Source References

Current checked-in addresses were taken from the official Mezo documentation:

- Mezo Pools: `https://mezo.org/docs/developers/features/mezo-pools/`
- MUSD Redemptions / contract addresses: `https://mezo.org/docs/developers/musd/musd-redemptions/`
- Borrow & Mint MUSD: `https://mezo.org/docs/users/musd/mint-musd/`
