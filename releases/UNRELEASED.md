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
# Unreleased

- Added a pinned deterministic OTP source inventory covering 36 applications
  and 1,268 Erlang modules, plus 981 native, Java, generator, and public-header
  production units, with explicit compatibility rows and coverage laws.
- Added a source-digest-pinned inventory of 40,563 exported functions, exported
  types, required callbacks, and optional callbacks, each represented by a
  stable compatibility row.
- Added a source-digest-pinned inventory of 11,780 public Erlang header records,
  macros, and types with semantic deduplication and explicit compatibility rows.
- Added a compiler-, source-, and class-digest-pinned inventory of 730 public or
  protected JInterface JVM symbols, preserving overload descriptors, generics,
  exceptions, visibility, and synthetic bridge metadata.
- Added a source-digest-pinned inventory of 15 production NIF modules, 279
  Erlang-callable NIF functions, and 2 drivers, preserving lifecycle hooks and
  scheduler flags.
- Corrected production-source classification to exclude singular `example/`
  trees as well as plural test/example paths.
- Added compiler- and source-digest-pinned C ABI inventories for Darwin ARM64,
  Linux AMD64/ARM64, and Windows AMD64, covering 3,535 profile-qualified NIF,
  driver, and EI functions, types, layouts, enums, and variables.
- Added compiler-profiled inventories of 1,047 active, OTP-owned NIF, driver,
  and EI macros across Darwin ARM64, Linux AMD64/ARM64, and Windows AMD64.
