# Mezo Testnet Deployment

Current deployed TreasuryOS stack for Mezo Testnet, chain ID `31611`.

## Protocol Core

| Contract | Address |
| --- | --- |
| ProtocolFeeVault | `0x7fC3a5eDdf210Ef293bfCcb239C297100d828C5E` |
| ProtocolFeeManager | `0x14F3E3B3525d50208E026D7C5F7652Be820c5462` |
| TreasuryPolicyEngine | `0x9b4e0b6CbEFAD888af30597f2c902d8e18Ba5D5a` |
| BTCReservePolicy | `0xa486D433ee320a714d162a7cf9276b419cEb66e0` |
| TreasuryAccount implementation | `0xF96C2b1Fe8dC48552D009908a9E440D38a014a41` |
| TreasuryAccountFactory | `0x70caAaD8D018Db67751a919A84Df45bf9B4AdC84` |

`TreasuryAccountFactory` deploys EIP-1167 clones of the implementation.

## Client Treasury

| Contract | Address |
| --- | --- |
| Client TreasuryMultisig | `0x8b6613F44E6706b96Ea5CeD45Fa6AaA616cc3A5e` |
| TreasuryAccount clone | `0xa90Fe7E09c5c5f10CF7CFC07ec1d90E58203d989` |
| TreasuryAutomationExecutor | `0x056a5eff7B136c844B5915e10C39EcbC22115856` |
| AllocationRouter | `0x6296110Dcb6eC11EC9Ad6909785Aa191192Df98E` |
| MUSDSavingsRateHandler | `0xe64A7EC77a7846102d9d0749b4315F57BF6Ae801` |
| TigrisStablePoolHandler | `0x1FffBA313d6d2b934A065702B8dD3D8f1159e4CA` |

Client control mode is a one-signer TreasuryMultisig for the beginning. The TreasuryAccount owner is the
TreasuryMultisig, not an EOA.

The current TreasuryMultisig supports a one-shot native BTC proposal flow:
`proposeTransaction{value: collateral}(treasuryAccount, collateral, openTroveCalldata, txIdOffchain)`. For the 1-of-1
demo multisig this executes immediately, so a new client can connect with BTC and open a Mezo-backed TreasuryOS
position without first pre-funding the multisig in a separate transaction.

For live MUSD sleeve deposits, route through the client `AllocationRouter`, not the direct accounting-only
`TreasuryAccount.allocate(...)` function. The savings execution path is:

```bash
DATA=$(cast calldata "deposit(address,address,uint256)" "$TREASURY_ACCOUNT" "$MEZO_MUSD_SAVINGS_RATE" 1000000000000000000000)
cast send "$CLIENT_TREASURY_MULTISIG" \
  "proposeTransaction(address,uint256,bytes,bytes32)(uint256)" \
  "$ALLOCATION_ROUTER" 0 "$DATA" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url "$MEZO_RPC" \
  --private-key "$OWNER_PRIVATE_KEY"
```

The expected proof is both token-level and accounting-level: MUSD transfers from `TreasuryAccount` into
`MEZO_MUSD_SAVINGS_RATE`, `MEZO_MUSD_SAVINGS_RATE.balanceOf(TREASURY_ACCOUNT)` increases, `idleMUSD` decreases, and
`destinationAllocations(MEZO_MUSD_SAVINGS_RATE)` increases. `TreasuryAccount.allocate(...)` is only internal/demo
accounting and does not move MUSD into a live destination.

## Fee Status

Fee infrastructure is deployed and available to the system, but fees are disabled for the demo:

- `ProtocolFeeManager.feeVault()` is `0x7fC3a5eDdf210Ef293bfCcb239C297100d828C5E`
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

- Current listed contracts verify with optimizer runs `1`, via-IR, and standard JSON source.
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
PROTOCOL_FEE_VAULT=0x7fC3a5eDdf210Ef293bfCcb239C297100d828C5E
PROTOCOL_FEE_MANAGER=0x14F3E3B3525d50208E026D7C5F7652Be820c5462
TREASURY_POLICY_ENGINE=0x9b4e0b6CbEFAD888af30597f2c902d8e18Ba5D5a
BTC_RESERVE_POLICY=0xa486D433ee320a714d162a7cf9276b419cEb66e0
TREASURY_ACCOUNT_IMPLEMENTATION=0xF96C2b1Fe8dC48552D009908a9E440D38a014a41
TREASURY_ACCOUNT_FACTORY=0x70caAaD8D018Db67751a919A84Df45bf9B4AdC84

CLIENT_TREASURY_MULTISIG=0x8b6613F44E6706b96Ea5CeD45Fa6AaA616cc3A5e
TREASURY_ACCOUNT=0xa90Fe7E09c5c5f10CF7CFC07ec1d90E58203d989
RISK_KEEPER_TREASURY_ACCOUNT=0xa90Fe7E09c5c5f10CF7CFC07ec1d90E58203d989
TREASURY_AUTOMATION_EXECUTOR=0x056a5eff7B136c844B5915e10C39EcbC22115856
RISK_KEEPER_AUTOMATION_EXECUTOR=0x056a5eff7B136c844B5915e10C39EcbC22115856
ALLOCATION_ROUTER=0x6296110Dcb6eC11EC9Ad6909785Aa191192Df98E
MUSD_SAVINGS_RATE_HANDLER=0xe64A7EC77a7846102d9d0749b4315F57BF6Ae801
TIGRIS_STABLE_POOL_HANDLER=0x1FffBA313d6d2b934A065702B8dD3D8f1159e4CA
```

`RISK_KEEPER_PUBLIC_KEY` and `RISK_KEEPER_PRIVATE_KEY` can remain in `.env`. The keeper EOA is allowlisted. The client
multisig called `TreasuryAutomationExecutor.setAutomationOperator(RISK_KEEPER_PUBLIC_KEY, true)` during the client setup
batch.

Execute mode should still require `RISK_KEEPER_EXECUTE_CONFIRM=true` and `RISK_KEEPER_MAX_ACTIONS_PER_RUN=1`.
