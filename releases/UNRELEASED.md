# GoTP unreleased

- Artifact: `release:gotp.unreleased`
- Specification: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.compatibility-evidence`

## Added

- A deterministic OTP 29.0.4 compatibility-ledger schema.
- Stable capability identities, assurance levels, and evidence requirements.
- `gotp parity` for a machine-readable summary.
- An intentionally incomplete bootstrap inventory that prevents false parity claims.
- A positive reduction-budget capability with exhaustive exhausted/quiescent outcomes and property-tested round-robin laws.
- Resumable VM continuations with OTP-pinned call/return reduction accounting and partition-invariance laws.
- An ERTS adapter that schedules VM continuations as kernel processes with structured completion and failure exits.
- A strict separation between encoded BEAM operands and immutable Erlang runtime terms in VM registers.
- Explicit VM host capabilities with reduction-counted `send/0` integrated through kernel context authority.
- Persistent selective-receive cursors implementing `loop_rec`, `loop_rec_end`, `remove_message`, and `wait`.
- Race-safe clock-driven process wakeups using explicit `std/clock` capabilities and cancellable timers.

This document is not a release and does not authorize a tag or publication.
