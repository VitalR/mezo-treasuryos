# Mezo Testnet Deployment

Current deployed TreasuryOS stack for Mezo Testnet, chain ID `31611`.

## Protocol Core

| Contract | Address |
| --- | --- |
| TreasuryPolicyEngine | `0xe43737328BB3C20bE484B1376F931391062cC2e7` |
| BTCReservePolicy | `0x4d6054bb0BFDEcBDA3599681EfEa383c1F63afAe` |
| TreasuryAccount implementation | `0xCc54C379A3f6A410BFC2cCeeB947953E1DD8BB36` |
| TreasuryAccountFactory | `0xC28e6f7C166b2bDa783AF9f0DD864147aFE0AcD2` |

`TreasuryAccountFactory` deploys EIP-1167 clones of the implementation. The implementation above is the canonical source
address for clone ABI/source verification.

## Client Treasury

| Contract | Address |
| --- | --- |
| Client TreasuryMultisig | `0x25a1FA3cF0597468eB35539712243d9e7B6FDBe3` |
| TreasuryAccount clone | `0xaB79775A1995AD280B2A32cB0127734eEa677ac7` |
| TreasuryAutomationExecutor | `0xD5b3Bc3515aEA5A94b997B0525a4B510E71d25bF` |
| AllocationRouter | `0xf6FC1ff6c6eE770Ff3e6A1f99B3DdD668538338E` |
| MUSDSavingsRateHandler | `0x801E185bCB70705B3CF3494caca948b6C48bc0fF` |
| TigrisStablePoolHandler | `0x4B761376fE6ABb6Fc00138217B3d7656c82FE785` |

Client control mode is a one-signer TreasuryMultisig for the beginning. The TreasuryAccount owner is the
TreasuryMultisig, not an EOA. The keeper EOA is the protocol-operated gas payer and is allowlisted on this client's
`TreasuryAutomationExecutor`.

## Fee Infrastructure

These contracts are deployed for future monetization and subscription/service accounting, but they are disabled for the
hackathon demo and are not core treasury execution contracts.

| Contract | Address |
| --- | --- |
| ProtocolFeeVault | `0x78c29c1A7BE2cd2F770AC88DF7a169aD3910EE3d` |
| ProtocolFeeManager | `0x5227B80cb9D23d0004e947777782fe9EB13Fa019` |

## Allocation UX

The fixed deployment supports the product-facing call path:

```bash
DATA=$(cast calldata "allocate(address,uint256)" "$MEZO_MUSD_SAVINGS_RATE" 1000000000000000000000)
cast send "$CLIENT_TREASURY_MULTISIG" \
  "proposeTransaction(address,uint256,bytes,bytes32)(uint256)" \
  "$TREASURY_ACCOUNT" 0 "$DATA" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url "$MEZO_RPC" \
  --private-key "$OWNER_PRIVATE_KEY"
```

If `AllocationRouter.handlers(destination)` is registered, `TreasuryAccount.allocate(destination, amount)` dispatches
through the router and live handler. For the MUSD Savings Vault this transfers MUSD from the TreasuryAccount to the
Savings vault, mints sMUSD to the TreasuryAccount, decreases `idleMUSD`, and increases
`destinationAllocations(destination)`.

Explorer note: the final demo allocation transaction is sent through the client `TreasuryMultisig` to
`TreasuryAccount.allocate`, which internally calls `AllocationRouter.depositFor` and then the registered handler. The
router dispatch does not emit a deposit event, so the router address page may only show deployment and handler
registration logs. The allocation proof is the successful TreasuryMultisig/TreasuryAccount transaction plus MUSD/sMUSD
token transfers, `TreasuryAccount.AllocationExecuted`, and `MUSDSavingsRateHandler` deposit events. The handler is
router-gated, so its deposit event proves the router path was used.

If no handler is registered, `allocate(...)` remains a manual accounting-only path for externally settled destinations.
Do not use an unregistered live destination as demo proof of deployed capital.

The direct router path is still valid for operators and scripts:

```bash
DATA=$(cast calldata "deposit(address,address,uint256)" "$TREASURY_ACCOUNT" "$MEZO_MUSD_SAVINGS_RATE" 1000000000000000000000)
cast send "$CLIENT_TREASURY_MULTISIG" \
  "proposeTransaction(address,uint256,bytes,bytes32)(uint256)" \
  "$ALLOCATION_ROUTER" 0 "$DATA" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url "$MEZO_RPC" \
  --private-key "$OWNER_PRIVATE_KEY"
```

## Fee Status

Fee infrastructure is deployed and available to the system, but fees are disabled for the demo:

- `ProtocolFeeManager.feeVault()` is `0x78c29c1A7BE2cd2F770AC88DF7a169aD3910EE3d`
- `ProtocolFeeManager.feesEnabled()` is `false`
- `performanceFeeBps` is `0`
- `originationFeeBps` is `0`
- `optimizationActionFeeBps` is `0`
- treasury execution flows do not call fee contracts

Fee receiver is the protocol vault contract, not an EOA.

## Source Verification Status

All listed TreasuryOS implementation/full contracts have deployed bytecode on Mezo Testnet and verified source on
Blockscout. The TreasuryAccount clone is an EIP-1167 proxy; verify the implementation source for source review.

Verification endpoint:

- `https://api.explorer.test.mezo.org/api/`

Use:

```bash
make verify-mezo-testnet-status
make verify-mezo-testnet-deployed
```

## Local Environment Addresses

Set these public address variables for demo scripts and keeper proposal mode. Use plain `KEY=value` in `.env`; quotes are
not needed for addresses or numeric values.

```bash
PROTOCOL_FEE_VAULT=0x78c29c1A7BE2cd2F770AC88DF7a169aD3910EE3d
PROTOCOL_FEE_MANAGER=0x5227B80cb9D23d0004e947777782fe9EB13Fa019
TREASURY_POLICY_ENGINE=0xe43737328BB3C20bE484B1376F931391062cC2e7
BTC_RESERVE_POLICY=0x4d6054bb0BFDEcBDA3599681EfEa383c1F63afAe
TREASURY_ACCOUNT_IMPLEMENTATION=0xCc54C379A3f6A410BFC2cCeeB947953E1DD8BB36
TREASURY_ACCOUNT_FACTORY=0xC28e6f7C166b2bDa783AF9f0DD864147aFE0AcD2

CLIENT_TREASURY_MULTISIG=0x25a1FA3cF0597468eB35539712243d9e7B6FDBe3
TREASURY_ACCOUNT=0xaB79775A1995AD280B2A32cB0127734eEa677ac7
RISK_KEEPER_TREASURY_ACCOUNT=0xaB79775A1995AD280B2A32cB0127734eEa677ac7
TREASURY_AUTOMATION_EXECUTOR=0xD5b3Bc3515aEA5A94b997B0525a4B510E71d25bF
RISK_KEEPER_AUTOMATION_EXECUTOR=0xD5b3Bc3515aEA5A94b997B0525a4B510E71d25bF
ALLOCATION_ROUTER=0xf6FC1ff6c6eE770Ff3e6A1f99B3DdD668538338E
MUSD_SAVINGS_RATE_HANDLER=0x801E185bCB70705B3CF3494caca948b6C48bc0fF
TIGRIS_STABLE_POOL_HANDLER=0x4B761376fE6ABb6Fc00138217B3d7656c82FE785
```

`RISK_KEEPER_PUBLIC_KEY` and `RISK_KEEPER_PRIVATE_KEY` can remain in `.env`. Execute mode should still require
`RISK_KEEPER_EXECUTE_CONFIRM=true` and `RISK_KEEPER_MAX_ACTIONS_PER_RUN=1`.

## Retired Stack

The previous client stack was retired after an allocation UX issue was found. Its MUSD Savings exposure was unwound,
the trove was closed, native BTC collateral was recovered, and remaining MUSD tokens were returned to the owner.

Retired addresses:

- Client TreasuryMultisig: `0x8b6613F44E6706b96Ea5CeD45Fa6AaA616cc3A5e`
- TreasuryAccount: `0xa90Fe7E09c5c5f10CF7CFC07ec1d90E58203d989`
- AllocationRouter: `0x6296110Dcb6eC11EC9Ad6909785Aa191192Df98E`
- TreasuryAutomationExecutor: `0x056a5eff7B136c844B5915e10C39EcbC22115856`

Do not use the retired stack for demos. Its token balances are zero and debt/collateral are zero, but its internal idle
BTC/MUSD accounting contains stale legacy values because recovery used a one-off handler on the old router.
