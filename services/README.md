# Services

This folder will contain the offchain product layer for Mezo TreasuryOS.

Planned V1 services:

- treasury state service
- treasury operations engine
- reporting service
- Treasury Yield Console data service
- AI Treasury Allocation Advisor memo generator
- Term Yield Planner for 7/30/60-day planning assumptions
- API layer

These services should consume the same Mezo testnet configuration and use Spectrum Nodes as the primary RPC provider in the hackathon environment.

Current runnable services:

- `services/spectrum-state/rpc-health.mjs`: multi-endpoint Spectrum-first RPC health check
- `services/spectrum-state`: Spectrum-first Mezo testnet RPC state reader with `MEZO_RPC_URL` fallback
- `services/yield-console`: console/reporting renderer for treasury yield allocation snapshots

The AI advisor is advisory only. It should consume deterministic onchain state and policy-decision previews, then generate recommendation memos for operators and reviewers. It must never control funds or bypass `TreasuryPolicyEngine`.
