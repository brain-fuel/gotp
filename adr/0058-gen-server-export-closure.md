# ADR 0058: Close the pinned gen_server runtime export surface

## Status

Accepted.

## Context

Lifecycle slices proved most public `gen_server` operations, but the ledger
still omitted direct initialization, broadcast, custom stop, and system
callback exports. The requested `wake_hib/6` continuation existed in older OTP
releases but is not exported by OTP 29.0.4; this release uses internal
`loop_hibernate/4` and `loop_wakeup/4` with `erlang:hibernate/0,3`.

## Decision

Execute `init_it/6` directly only from correctly initialized `proc_lib`
children. Differentially cover all initialization result families,
acknowledgement, cleanup, ancestry, and callback failure. Execute delayed
hibernate/wake lifecycles through ordinary callbacks, timeout and system paths,
malformed post-wake behavior, and linked-parent failure.

Implement `erlang:hibernate/0` as the GC boundary before the existing receive
loop and `erlang:hibernate/3` as a validated tail transfer to the requested
MFA. Prove all other missing public exports through the same isolated corpus.

Add a verifier over the pinned BEAM export table and compatibility ledger.
Compiler metadata exports receive explicit classifications; every public
runtime export must have a ledger row that is proved or carries a precise
missing reason. The verifier also asserts that `wake_hib/6` is absent.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by `gotp.erts.otp29-gen-server-remaining-runtime`,
`gotp.erts.gen-server-hibernate-wake-equivalence`, and
`gotp.erts.otp29-gen-server-export-ledger-coverage`.

## Consequences

Every OTP 29.0.4 `gen_server.beam` runtime export is now represented by
executable evidence and a ledger classification. Rows remain partial where
their complete Erlang term, distributed, timing, or failure domains remain
open; this does not claim complete semantic parity for the module.
