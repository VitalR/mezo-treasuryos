# ABI Placeholder

Copy verified ABI JSON files from `contracts/out/**` into this directory before running Goldsky codegen.

Expected files:

- `AllocationRouter.json`
- `MUSDSavingsRateHandler.json`
- `TigrisStablePoolHandler.json`
- `TreasuryAccount.json`
- `TreasuryAccountFactory.json`
- `TreasuryAutomationExecutor.json`
- `TreasuryMultisig.json`
- `TreasuryPolicyEngine.json`

Do not hand-write fake ABIs. Use Foundry artifacts from the exact commit being deployed.
