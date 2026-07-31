# Hot code loading is a two-version state machine

- ADR: `adr:gotp.two-version-hot-code-state`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.beam.hot-code`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Represent loaded code as an immutable transition system with at most one
current and one old generation per module. Loading a replacement moves current
to old. Reject a third generation until old code is purged. Track execution
references by generation so soft purge refuses live old code and forced purge
reports and invalidates every affected reference.

Clone BEAM module images at transition and observation boundaries. This keeps
the value-state invariant independent of mutation through exported interop
structures. An ERTS adapter associates references with process identities and
uses an explicit exit capability to terminate each forced-purge process once.
VM linked-code resolution acquires a generation lease at each fully qualified
call. Return frames preserve the caller image and lease; return, tail-call,
halt, and exception-unwind paths release abandoned generations exactly once.
The ERTS resolver serves the `LoadedModule` image owned by that same generation.

Typed `gen_server` callbacks expose atomic `code_change(OldVsn, State, Extra)`
migration: failed callbacks preserve the prior state and successful callbacks
publish the replacement state as one transition.
The server processes sender-checked OTP system envelopes through selective
receive. Suspension leaves ordinary calls, casts, and info messages queued;
`change_code` is accepted only while suspended; resume restores normal mailbox
dispatch after an acknowledged migration.

## Consequences

The core two-version and soft-purge rules are total, deterministic, and free of
ambient effects. Purging drops generation-owned VM images and literals after
leases drain. System state inspection/replacement, OTP-shaped status reports,
and acknowledged termination use explicit codecs and callbacks. Debug controls,
release handlers, application upgrade scripts, and emulator-level literal
arenas remain explicit work under the partial `system.hot-code` capability.

## Evidence

`test:gotp.beam.hot-code-laws` proves the two-version bound, third-load
rejection, current/old promotion, active-reference soft-purge refusal,
forced-purge invalidation, and image non-aliasing over generated transition
sequences.

`test:gotp.erts.hot-code-laws` proves reference ownership, effect-free soft
purge, one exit per affected process, and the OTP `killed` forced-purge reason.

`test:gotp.vm.hot-code-call-laws` proves current-generation resolution, old
caller continuation, and exactly-once lease release for ordinary and tail
calls. `test:gotp.otp.gen-server-code-change-laws` proves atomic typed state
migration and rollback on callback failure.

`test:gotp.otp.gen-server-system-laws` proves sender-checked acknowledgements,
suspended selective receive, suspended-only migration, and post-resume queued
event dispatch.
The same laws cover OTP-shaped get-state, replace-state, status, and terminate
commands with atomic replacement rollback.
