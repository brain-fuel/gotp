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
- Added an immutable two-version hot-code state machine with generation-scoped
  execution references, soft-purge safety, and forced-purge invalidation laws.
- Added generation-leased VM linked calls that enter current code while return
  frames retain old code, plus atomic typed `gen_server` `code_change` state
  migration and purged-generation VM image reclamation.
- Added sender-checked `gen_server` system suspend/change/resume handling with
  selective mailbox dispatch and deterministic acknowledgements.
- Added OTP-shaped system state inspection/replacement, status reports, and
  acknowledged termination through explicit typed codecs and callbacks.
- Added capability-scoped `sys` trace, bounded log, and statistics controls
  using deterministic `std/clock` timestamps and property-tested retention.
- Added a total typed parser and transaction validator for the pinned low-level
  relup instruction vocabulary and `point_of_no_return` ordering.
- Added a capability-neutral release executor with reverse preflight rollback,
  irreversible commit failures, and explicit emulator-restart outcomes.

### ERTS release execution

- Added `gotp.erts.release-runtime`, which connects typed release scripts to
  two-version module loading and purge semantics through explicit effect
  capabilities.
- Added laws for commit ordering, deferred post-load purge, and rejection of a
  busy soft pre-purge.
- This is an unreleased compatibility slice. It does not establish OTP feature
  parity, and the compatibility inventory remains incomplete.

### Typed appup and relup foundations

- Added ordered, typed `.appup` parsing and exact/full-regex version selection.
- Added deterministic upgrade/downgrade release-delta assembly for changed,
  added, and removed applications and emulator restart placement.
- `systools_rc` translation and the remaining `systools_relup` surface are not
  complete; no OTP parity claim is made.

### Typed systools release compiler

- Added sealed high-level release instructions and deterministic compilation to
  executable transactional release scripts.
- Added application lifecycle expansion, module dependency validation,
  upgrade/downgrade ordering, object-code merging, and restart canonicalization.
- Raw Erlang instruction decoding and differential `systools_rc` parity remain
  incomplete; no OTP parity claim is made.
- Added total raw high-level instruction decoding and a direct relup-delta to
  executable-script bridge; differential OTP ordering proof remains open.

### Generation-owned literal memory

- Added grouped reset/release and generic SoA layout primitives to Go+ std
  memory, with property laws for invalidation, reuse, and AoS round trips.
- Added an ERTS literal arena as a second consumer with secure generation reset
  and immutable-copy reads.
- Loader and hot-code purge integration remain open; no ERTS parity claim is
  made.
- Connected BEAM `LitT` ownership to loaded modules and generation-aware
  hot-code purge; leased old code retains literals until soft purge succeeds.
- Added typed current-code removal with lease-aware soft rejection and forced
  owner termination and literal-generation reclamation; release `remove` now
  uses this state transition directly.

### Process-owned message buffers

- Added a generic Go+ std typed buffer whose removal/reset/release operations
  clear GC-visible references and support allocation reuse.
- Migrated VM selective-receive fragments to the typed buffer and release the
  entire mailbox fragment group on completion, uncaught exception, or failure.
- Register, continuation, heap, signal-queue, binary, and scheduler-cache memory
  remain open; no ERTS memory parity claim is made.
