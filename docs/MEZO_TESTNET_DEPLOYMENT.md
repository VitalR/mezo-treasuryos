# Mezo Testnet Deployment

Current deployed TreasuryOS stack for Mezo Testnet, chain ID `31611`.

## Protocol Core

| Contract | Address |
| --- | --- |
| ProtocolFeeVault | `0x178C198D6780694dE144B6dc6817FC4cB6f4C515` |
| ProtocolFeeManager | `0x7E866b7D7E6Eb20C555b0ec0E1706885e8742Bb4` |
| TreasuryPolicyEngine | `0x2C97289f876A568031A20077D789A03D1EEAd351` |
| BTCReservePolicy | `0x216d32FD2627329F0C9b77942ce5E2130969E232` |
| TreasuryAccount implementation | `0xF7192AdcC0256193f35a1FAA42fe1b2f967f5728` |
| TreasuryAccountFactory | `0x221d519E0081BE615590db0b0D1D7bae3260B333` |

`TreasuryAccountFactory` deploys EIP-1167 clones of the implementation.

## Client Treasury

| Contract | Address |
| --- | --- |
| Client TreasuryMultisig | `0x820a77dF1924069Fa65a2bcBb6C0490E3083bba6` |
| TreasuryAccount clone | `0xE9Bd6B6EfD80f4d2859edBAb2Ae5468c60fEdde1` |
| TreasuryAutomationExecutor | `0x911e21de620D788D45242D843aEaBC00ccEAD372` |
| AllocationRouter | `0x47350e99d38640b403E2996e1872F5B44669907b` |
| MUSDSavingsRateHandler | `0x0A7E23d454FCF8925c674e0f3A770e8DdabE8503` |
| TigrisStablePoolHandler | `0x7FD39FB91F3CD47b5dB58a148491252962119CBE` |

Client control mode is a one-signer TreasuryMultisig for the beginning. The TreasuryAccount owner is the
TreasuryMultisig, not an EOA.

## Fee Status

Fee infrastructure is deployed and available to the system, but fees are disabled for the demo:

- `ProtocolFeeManager.feeVault()` is `0x178C198D6780694dE144B6dc6817FC4cB6f4C515`
- `ProtocolFeeManager.feesEnabled()` is `false`
- `performanceFeeBps` is `0`
- `originationFeeBps` is `0`
- `optimizationActionFeeBps` is `0`
- treasury execution flows do not call fee contracts

Fee receiver is the protocol vault contract, not an EOA.

## Source Verification Status

All listed TreasuryOS contracts have deployed bytecode on Mezo Testnet and have verified source on Blockscout.

Verification endpoint:

- `https://api.explorer.test.mezo.org/api/`

Verification profile notes:

- `ProtocolFeeVault`, `ProtocolFeeManager`, `TreasuryPolicyEngine`, and `BTCReservePolicy` were deployed before the
  clone-size compiler profile change. They verify with optimizer runs `1000`, no via-IR, and flattened source.
- `TreasuryAccount` implementation, `TreasuryAccountFactory`, `TreasuryMultisig`, `TreasuryAutomationExecutor`,
  `AllocationRouter`, `MUSDSavingsRateHandler`, and `TigrisStablePoolHandler` verify with optimizer runs `1`, via-IR,
  and standard JSON source.
- `TreasuryAccount` clone is a 45-byte EIP-1167 proxy. Blockscout reports it with the verified `TreasuryAccount` ABI;
  the canonical source address remains the `TreasuryAccount` implementation.

Use:

```bash
make verify-mezo-testnet-status
make verify-mezo-testnet-deployed
```

## Local Environment Addresses

Set these public address variables for demo scripts and keeper proposal mode:

```bash
PROTOCOL_FEE_VAULT=0x178C198D6780694dE144B6dc6817FC4cB6f4C515
PROTOCOL_FEE_MANAGER=0x7E866b7D7E6Eb20C555b0ec0E1706885e8742Bb4
TREASURY_POLICY_ENGINE=0x2C97289f876A568031A20077D789A03D1EEAd351
BTC_RESERVE_POLICY=0x216d32FD2627329F0C9b77942ce5E2130969E232
TREASURY_ACCOUNT_IMPLEMENTATION=0xF7192AdcC0256193f35a1FAA42fe1b2f967f5728
TREASURY_ACCOUNT_FACTORY=0x221d519E0081BE615590db0b0D1D7bae3260B333

CLIENT_TREASURY_MULTISIG=0x820a77dF1924069Fa65a2bcBb6C0490E3083bba6
TREASURY_ACCOUNT=0xE9Bd6B6EfD80f4d2859edBAb2Ae5468c60fEdde1
RISK_KEEPER_TREASURY_ACCOUNT=0xE9Bd6B6EfD80f4d2859edBAb2Ae5468c60fEdde1
TREASURY_AUTOMATION_EXECUTOR=0x911e21de620D788D45242D843aEaBC00ccEAD372
RISK_KEEPER_AUTOMATION_EXECUTOR=0x911e21de620D788D45242D843aEaBC00ccEAD372
ALLOCATION_ROUTER=0x47350e99d38640b403E2996e1872F5B44669907b
MUSD_SAVINGS_RATE_HANDLER=0x0A7E23d454FCF8925c674e0f3A770e8DdabE8503
TIGRIS_STABLE_POOL_HANDLER=0x7FD39FB91F3CD47b5dB58a148491252962119CBE
```

`RISK_KEEPER_PUBLIC_KEY` and `RISK_KEEPER_PRIVATE_KEY` can remain in `.env`. The keeper EOA is allowlisted. The client
multisig called `TreasuryAutomationExecutor.setAutomationOperator(RISK_KEEPER_PUBLIC_KEY, true)` in transaction
`0x28e028b3740840a2a57229b07a665a34c483ad82b810fa81d847d270793de011`.

Execute mode should still require `RISK_KEEPER_EXECUTE_CONFIRM=true` and `RISK_KEEPER_MAX_ACTIONS_PER_RUN=1`.
