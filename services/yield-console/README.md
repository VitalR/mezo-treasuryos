# Treasury Yield Console

Dependency-free demo renderer for the V1 yield allocation surface.

It consumes a treasury snapshot shaped like the onchain read model:

- idle MUSD
- required operating buffer
- allocatable surplus
- sleeve exposure and caps
- collateral health
- allocation policy decision

Run from the repo root:

```sh
node services/yield-console/render.mjs services/yield-console/sample-snapshot.json
```

This is not an autonomous allocator. The memo is a deterministic, policy-aware advisor scaffold for the demo and should later be backed by live reads plus an AI summarization step.
