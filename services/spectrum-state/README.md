# Spectrum State Service

Dependency-free TreasuryOS state reader for the Mezo testnet demo.

RPC selection is intentionally Spectrum-first and reads the real root `.env` file:

1. `SPECTRUM_MEZO_RPC_URL_1`
2. `SPECTRUM_MEZO_RPC_URL_2`
3. `SPECTRUM_MEZO_RPC_URL_3`
4. `SPECTRUM_MEZO_RPC_URL`
5. fallback to `MEZO_RPC_URL`

The script probes `eth_chainId` and only selects an endpoint if it returns Mezo testnet chain ID `31611`. This lets us try multiple Spectrum URL shapes while preserving a working fallback to the official Mezo testnet RPC if a candidate is not an EVM JSON-RPC endpoint.

Check all configured RPC candidates:

```sh
make rpc-health
```

Probe the selected RPC:

```sh
npm run state:probe
```

Inspect the configured Mezo yield targets through the selected RPC:

```sh
make yield-targets
```

Inspect the `mcbBTC/BTC` BTC sleeve mechanics through the selected RPC:

```sh
make btc-sleeve-targets
```

This checks the BTC precompile/BTCCaller metadata, mcbBTC metadata, pool reserves, UI-observed swap/add-liquidity/stake transactions, router code hashes, and LP gauge metadata. It does not move funds.

Build a live snapshot from an onboarding manifest:

```sh
npm run state:snapshot -- --manifest deployments/mezo-testnet-client.json --out /tmp/treasuryos-snapshot.json
node services/yield-console/render.mjs /tmp/treasuryos-snapshot.json
node services/term-yield-planner/run.mjs /tmp/treasuryos-snapshot.json
```

Or pass addresses directly:

```sh
node services/spectrum-state/snapshot.mjs \
  --treasury-account 0x... \
  --destinations 0x...,0x... \
  --actor 0x... \
  --out /tmp/treasuryos-snapshot.json
```

If a deployed `BTCReservePolicy` address is present in the manifest, the snapshot also reads BTC reserve buckets and
BTC policy config. To preview a BTC-correlated sleeve candidate:

```sh
node services/spectrum-state/snapshot.mjs \
  --manifest deployments/mezo-testnet-client.json \
  --proposed-btc-sleeve 0xc8BA1027e1D4f9C646B9963Eab89B1e7CF2A476E \
  --proposed-btc-amount 0.05 \
  --out /tmp/treasuryos-snapshot.json
```

Reads currently covered:

- RPC chain and block probe
- MUSD Savings Vault and Tigris yield target metadata
- BTC precompile, mcbBTC/BTC pool, and gauge inspection for BTC sleeve planning
- idle MUSD and idle BTC
- Treasury Account position debt/collateral
- collateral-health state
- policy buffer and approval threshold
- sleeve allocation/cap/receipt balances
- `previewAllocation(...)` policy decision result
- optional `BTCReservePolicy` bucket, policy, sleeve, and preview reads

This service is the bridge between Spectrum RPC and the Yield Console / AI memo layer.
