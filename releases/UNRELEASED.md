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
- OTP receive timeouts with explicit timer authority, deterministic fake-clock laws, and message-selection cancellation (`ADR-0009`).
- Process-isolated BEAM module loading with export validation and a pinned OTP-29.0.4 artifact law (`ADR-0010`).
- Bounded OTP `LitT` materialization for uncompressed and legacy zlib literal pools, backed by ETF and full-runtime execution laws.
- Explicit `ImpT` linking and reduction-counted `call_ext`, `call_ext_only`, and `call_ext_last` execution through immutable MFA registries (`ADR-0011`).
- Core immutable list/tuple/type-test/select instructions, including direct execution of an OTP-29.0.4 `lists:reverse/1` fast path (`ADR-0012`).

This document is not a release and does not authorize a tag or publication.
