# ADR 0053: Prove gen_server adverse lifecycles with isolated OTP oracles

## Status

Accepted.

## Context

The first pinned lifecycle established ordinary start, messaging, stop, and
normal monitored exit. It did not establish the failure-sensitive behavior
applications depend on: links, timeout aliases, callback crashes, registration,
continuations, unsolicited messages, or system code change.

## Decision

Run each adverse lifecycle as an isolated callback export in OTP 29.0.4 and in
GoTP. Compare its encoded result against a deterministic checked-in corpus.
Execute the unmodified pinned `gen_server`, `gen`, `proc_lib`, and `sys` BEAM
modules; implement missing behavior as general VM, ERTS, or kernel semantics.
In particular, implement `update_record/5` as a generic one-based immutable
tuple update rather than special-casing the code-change path.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by assay artifacts `gotp.erts.otp29-gen-server-lifecycle` and
`gotp.vm.update-record-laws`; those identifiers bind documentation to generated
test manifests without fragile source line references.

## Consequences

The matrix proves partial compatibility for only the declarations and input
classes it executes. It does not prove complete `gen_server` or OTP parity.
Each scenario gets a fresh runtime so callback crashes and registered names
cannot contaminate later evidence.
