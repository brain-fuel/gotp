# OTP 29.0.4 compatibility specification

- Artifact: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.compatibility-evidence`
- Deployable unit: `code:gotp.compat.ledger`
- Upstream tag: `OTP-29.0.4`
- Upstream commit: `1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Required outcome

GoTP reaches semantic feature compatibility when the complete upstream
inventory is represented, every applicable capability is conformant under its
declared assurance level, and interoperability suites accept artifacts from
Erlang, Elixir, Gleam, LFE, and other BEAM producers without source changes.
API parity with Erlang/OTP is not required.

## Ledger rules

1. IDs are stable semantic identities and never contain source line numbers.
2. `conformant` entries include executable differential or property evidence.
3. `partial` and `missing` entries prevent a parity claim.
4. `unavailable` entries explain why an upstream capability is inapplicable.
5. `inventory_complete` is set only after the pinned upstream inventory is independently audited.
6. Canonical serialization sorts capabilities and evidence deterministically.

## Assurance

Each entry uses the GoTP proof vocabulary: `Foreign`, `BoundaryChecked`,
`ResourceSafe`, `Total`, or `ClosedVerified`. Assurance states what has been
established; it does not elevate compatibility status by itself.

## Current state

`compat/otp-29.0.4.json` is a bootstrap inventory. It deliberately sets
`inventory_complete` to false and records known gaps. It is not evidence of
feature parity.
