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

- Proved OTP 29.0.4 `gen_statem:format_log/1,2`, `format_status/2`, and modern
  and legacy status callbacks through isolated corpora for both callback modes.
  Covered crash and termination diagnostics, queued/postponed events, state,
  data, time-outs, Unicode, depth and character limits, normal and suspended
  status, sensitive-data redaction, malformed public inputs, and malformed
  callback returns. Added a generated determinism and callback-mode equivalence
  law and promoted only the seven directly evidenced declaration rows. Added a
  complete inventory law fixing the resulting boundary at 39 partial functions,
  14 partial callback declarations, and 25 missing exported types.

- Proved all fourteen OTP 29.0.4 `gen_statem` asynchronous request exports
  through byte-identical isolated corpora for `state_functions` and
  `handle_event_function`. Covered direct and labeled collection requests,
  wait/receive/check variants, collection creation/addition/introspection,
  deletion and retention, timeout retry and abandonment, late-reply
  suppression, crashes, dead servers, local names, out-of-order replies, and
  mailbox cleanliness. Added a stateful law over generated live-request release
  permutations and promoted only these fourteen declaration rows.

- Pinned the unmodified OTP 29.0.4 `gen_statem.beam` and added isolated,
  deterministic callback corpora for `state_functions` and
  `handle_event_function`. Added a machine-derived export-ledger verifier and
  a stateful callback-mode trace-equivalence law. Covered all construction and
  `enter_loop` arities, calls/casts/stops, state entry, internal/info/time-out
  events, next-event, postpone, hibernate, both repeat forms, direct and
  batched replies, callback-module change/push/pop, registration, proc-lib
  ancestry, linked-parent exits, system control, termination, and adverse
  callback returns. Promoted only the directly evidenced lifecycle rows.

- Closed the pinned OTP 29.0.4 `gen_server.beam` runtime export inventory with
  direct `init_it/6`, `abcast/2,3`, `stop/3`, and system-callback evidence.
  Added delayed hibernation wake differential cases and a stateful equivalence
  law across calls, casts, info, timeout, system control, malformed callbacks,
  termination, and parent exits. Added an export-ledger verifier and documented
  that OTP 29.0.4 no longer exports legacy `wake_hib/6`.

- Proved `gen_server:format_log/1,2` and `format_status/2`, including modern and
  legacy status callbacks, through an isolated OTP 29.0.4 corpus. Rendered
  termination, crash, no-handler, Unicode, depth, character-limit, and line-mode
  output is byte-exact; live normal and suspended status is differential, with
  deterministic-format and ordinary-versus-entered status laws.

- Proved `gen_server:enter_loop/3,4,5` through an isolated OTP 29.0.4 corpus
  covering proc-lib ancestry, local/global/via registration, initial timeout,
  hibernate and continue actions, lifecycle and system messages, code change,
  exact invalid initialization reasons, and linked-parent exits. Added a
  stateful law comparing randomized post-entry traces with ordinary servers.

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
- Added sealed `systools_relup` error and warning diagnostics with pinned OTP
  message text, prefix behavior, newline placement, and source-linked laws.
- Added a reproducible official OTP-29.0.4 container oracle, ETF-backed corpus,
  and differential laws for appup selector ordering/failure behavior and relup
  diagnostics; regex-engine and complete `~tp` parity remain open.
- Replaced RE2-only appup matching with MIT `regexp2` plus typed PCRE
  possessive-quantifier normalization; pinned differential cases now cover
  backreferences, lookaround, atomic groups, Unicode classes, and possessive
  repeats while complete PCRE2 proof remains open.

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
- Released the shared arena, group, SoA, and typed-buffer primitives as
  `goforge.dev/goplus/std@v0.210.0`; GoTP now consumes the published module
  without workspace or replacement resolution.
- Migrated VM selective-receive fragments to the typed buffer and release the
  entire mailbox fragment group on completion, uncaught exception, or failure.
- Register, continuation, heap, signal-queue, binary, and scheduler-cache memory
  remain open; no ERTS memory parity claim is made.
- Migrated X/Y registers to typed reusable buffers; Y deallocation clears
  removed slots, while terminal continuation paths clear X terms and release Y
  backing storage.
- Replaced parallel return slices with typed return frames and migrated return
  and exception stacks to clearing buffers with reverse, exactly-once code-lease
  release.
- Migrated kernel mailboxes, the scheduler run queue, and staged remote signals
  to clearing typed buffers; terminal processes release mailbox storage while
  scheduler-owned queues retain cleared capacity for reuse.
- Integrated the arena-backed process heap with BEAM heap checks and list/tuple
  construction, with grouped immutable roots and explicit off-heap ownership
  for binaries larger than 64 bytes.
- Added live-root copying collection and geometric heap growth over X/Y and
  pending exception roots, dropping unreachable construction roots and
  rebuilding off-heap binary ownership transactionally.

### OTP stdlib execution

- Replaced the bootstrap `lists.beam` fixture with the byte-identical module
  from the official OTP 29.0.4 image.
- Added deterministic OTP-oracle corpora covering every one of the module's 95
  exports, including higher-order operations invoked with pinned BEAM closures.
- Added the map instruction family, ordered comparison BIFs, and generic
  `module_info/0,1` metadata required by the unmodified module.
- Recorded the OTP VM-global export-table ordering boundary in ADR 0049. The 91
  source-declared `lists` rows remain partial until their complete input domains
  have differential or property evidence.
- Added byte-identical pinned fixtures for `maps`, `proplists`, `ordsets`,
  `queue`, `gb_sets`, and `gb_trees` from the same official OTP image.
- Executed all 37 `maps.beam` exports, including higher-order operations with
  BEAM closures, through deterministic OTP-oracle corpora.
- Added the native immutable map BIF surface, native and ordered map iteration,
  total-term comparison, integer remainder, and exported-function dispatch.
- Executed every export of the pinned `proplists`, `ordsets`, and `queue`
  modules, including their higher-order operations with BEAM closures.
- Added core `tuple_size`, `map_get`, `is_map_key`, numeric `==`, and `is_list`
  BIF behavior required by those modules.
- Executed every export of the pinned `gb_sets` and `gb_trees` modules against
  OTP-produced opaque tree values, including callback and iterator operations.
- Added arbitrary-precision `bsr` and `bsl` behavior used by tree balancing.
- Pinned the unmodified OTP 29.0.4 `gen_server.beam` and its direct import
  closure, and executed request-ID collection/introspection entry points with
  real ETF reference terms.
- Executed a pinned `gen_server` lifecycle through start, call, cast, explicit
  reply, system stop, callback termination, and monitored normal exit. Added
  receive-marker host effects, monitor-backed aliases, callable closure arity,
  monotonic time, loaded-function introspection, and exact exit-reason
  propagation required by that path. Broader lifecycle parity remains open.
- Expanded that corpus into an OTP-oracle adverse-lifecycle matrix covering
  linked and monitored starts, local named duplicate starts, call timeout with
  late-reply alias suppression, exact callback-crash and linked-parent exit
  reasons, continue and info callbacks, and suspended system code change.
- Added generic OTP 29 `update_record/5`, kernel-scoped `persistent_term`,
  process-dictionary enumeration, and MFA `spawn_monitor/3` semantics required
  by the unmodified pinned OTP modules. The record update has randomized
  replacement and source-immutability evidence.
- Proved all eight asynchronous `gen_server` request exports through isolated
  OTP 29.0.4 oracle cases: direct and collection success, retryable and
  abandoning timeouts, late-response suppression, exact crash errors, local
  names, out-of-order replies, and explicit response checks. Added a stateful
  property law over randomized live-request reply permutations.
- Proved `gen_server:multi_call/2,3,4` against a deterministic OTP peer-node
  corpus. Added a reusable virtual cluster that routes remote PID, registered
  name, alias, tagged-monitor, and monitor-exit signals across real kernels,
  with node identity/enumeration and cancelable message timers. Stateful laws
  randomize connectivity, registration, duplicate targets, reply order,
  bad-node classification, and mailbox cleanup.
