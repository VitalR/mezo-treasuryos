# Mezo TreasuryOS Docs Index

This folder contains the canonical product docs for **Mezo TreasuryOS**.

These documents reflect the current product direction:

- TreasuryOS as an institutional treasury operations layer
- direct Mezo borrow integration through the product
- isolated Treasury Accounts
- treasury policy controls
- governed allocation into Mezo-native destinations
- bounded automated treasury operations
- reviewer-facing reporting

---

## Canonical Docs

- `PRODUCT_VISION.md` — product thesis, positioning, customer, and product boundaries
- `PROJECT_SPEC.md` — V1 scope, required workflows, policies, and product requirements
- `ARCHITECTURE.md` — V1 system shape, control boundaries, and core components
- `ROADMAP.md` — build sequence and scope discipline for a 6-week implementation
- `JUDGE_PITCH.md` — compressed hackathon-facing narrative

---

## Draft Archive

Earlier V1 docs, exploratory reviews, and superseded drafts have been moved to:

- `draft/docs/`

That archive preserves the earlier thinking without mixing it into the primary product narrative.

---

## Current Naming Model

- **Product:** Mezo TreasuryOS
- **Per-client operating boundary:** Treasury Account
- **Internal controls layer:** Treasury Policy Engine
- **Borrow origination integration:** Mezo Borrow Integration
- **Operations layer:** Treasury Operations Engine
- **Destination layer:** Allocation Adapters
- **Reporting layer:** Treasury Reporting Layer

---

## Current V1 Spine

The current V1 is built around one workflow:

1. create a Treasury Account
2. configure policy and approvals
3. deposit BTC and borrow MUSD through TreasuryOS
4. receive MUSD into the Treasury Account
5. preserve required liquidity buffer
6. allocate approved surplus into a Mezo-native destination
7. trigger bounded automated treasury operations
8. produce treasury reporting

If the product does not support that end-to-end flow, it is outside the current V1 scope.
