# Treasury Profiles

TreasuryOS supports profile-driven recommendations offchain today and policy-driven enforcement onchain.

The current onboarding scripts configure policy directly through environment variables such as collateral-ratio
thresholds, liquidity buffer, approval threshold, sleeve caps, BTC reserve floor, and automation caps. The advisor and
keeper then read the selected profile and produce recommendations that remain bounded by those deployed policies.

## Profiles

| Profile | Intended user | Advisor posture |
| --- | --- | --- |
| `conservative` | BTC-heavy treasury prioritizing safety | Prefer MUSD Savings, large liquidity buffer, no BTC sleeve execution. |
| `balanced` | Default institutional demo profile | Use MUSD Savings first, allow limited stable LP after route-health checks. |
| `active` | Treasury willing to use more approved yield capacity | Allow higher stable LP share while healthy; BTC remains gated. |
| `aggressive-demo` | Judge/demo stress profile only | Shows higher-risk routing logic; not a production default. |

## Current Setup

Use profiles in advisor/demo commands:

```bash
TREASURY_PROFILE=balanced make advisor-opportunities
TREASURY_PROFILE=active make advisor-opportunities
```

The current deployed live treasury uses the balanced posture in the final demo. Its actual onchain policy remains the
source of truth:

- `TreasuryPolicyEngine` enforces collateral health, buffers, approval thresholds, and automation caps.
- `TreasuryAutomationExecutor` only exposes whitelisted bounded defensive actions.
- `TreasuryMultisig` remains the owner for sensitive treasury actions.

## Onboarding Mapping

For a future product CLI, `TREASURY_PROFILE=<profile>` should map into the onboarding env values before deploying the
client stack. Until that profile renderer is added, configure these directly:

- `DEMO_TREASURY_LIQUIDITY_BUFFER`
- `DEMO_TREASURY_APPROVAL_THRESHOLD`
- `DEMO_TREASURY_WARNING_COLLATERAL_RATIO_BPS`
- `DEMO_TREASURY_CRITICAL_COLLATERAL_RATIO_BPS`
- `DEMO_TREASURY_TARGET_COLLATERAL_RATIO_BPS`
- `DEMO_TREASURY_MIN_POST_STRESS_COLLATERAL_RATIO_BPS`
- `DEMO_TREASURY_MIN_IDLE_BTC_RESERVE`
- `DEMO_TREASURY_MAX_AUTO_BUFFER_RESTORE`
- `DEMO_TREASURY_MAX_AUTO_DEBT_REPAY`
- `DEMO_TREASURY_MAX_AUTO_IDLE_BTC_TOP_UP`
- `DEMO_SAVINGS_CAP`
- `DEMO_TIGRIS_CAP`

The product rule remains: the profile recommends, the deployed policy enforces.
