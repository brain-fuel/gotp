# ADR 0049: Module export metadata preserves the VM-global boundary

## Status

Accepted.

## Context

OTP 29.0.4 implements `erlang:get_module_info(Module, exports)` by traversing
the emulator's VM-wide export table and selecting entries for `Module`. Entries
may predate module loading because calls from already loaded modules create
stubs. Consequently, observable export order is not encoded by a module's
`ExpT` rows or function labels and varies with VM loading history.

Treating label order as export-table order produced a plausible but false
implementation. Requiring an isolated GoTP module set to reproduce the booted
OTP oracle's order would instead encode that oracle's unrelated loading
history.

## Decision

Loaded modules retain their decoded export entries and expose exact export
membership. Differential module-metadata laws compare export entries as a
multiset while comparing intrinsic metadata exactly. A future VM-global export
registry will own insertion order, unresolved stubs, invalidation, and
trampoline state; module metadata must query that registry once it exists.

This boundary follows OTP's `exported_from_module` implementation in
`erts/emulator/beam/erl_bif_info.c` and its staged export table in
`erts/emulator/beam/export.c` at tag `OTP-29.0.4`.

## Consequences

The implementation does not invent a module-local ordering rule. Current
single-module execution is deterministic and membership-compatible, but exact
VM-history-dependent order remains part of the export-registry parity slice.

## Traceability

- Specification: `spec/otp-stdlib-beam-parity.md`
- Source units: `gotp.erts.module-loader`, `gotp.erts.module-invocation`,
  `gotp.erts.call-registry`
- Laws: `gotp.erts.otp29-lists-differential`,
  `gotp.erts.otp29-lists-export-coverage`
