# ADR 0056: Enter gen_server loops through proc_lib metadata

## Status

Accepted.

## Context

`gen_server:enter_loop/3,4,5` converts an already running process into a system
server. Correct behavior depends on `proc_lib` ancestry, process registration,
system-message handling, callback lifecycle behavior, and linked-parent exits.

## Decision

Execute the unmodified OTP 29.0.4 `gen_server.beam` from processes initialized
by the pinned `proc_lib.beam`. Preserve OTP's unregistered
`process_info(Pid, registered_name)` shape, provide kernel-scoped global-name
registration, and treat `erlang:garbage_collect/0` as a contextual VM operation
so hibernating servers can re-enter their receive loop.

Compare all three exports with an isolated official-OTP corpus covering local,
global, and via registration; initial actions; lifecycle and system messages;
code change; termination; invalid initialization; and parent-link behavior.
Add a stateful property law comparing randomized post-entry operation traces
with an ordinarily started server.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by assay artifacts `gotp.erts.otp29-gen-server-enter-loop` and
`gotp.erts.gen-server-enter-loop-equivalence`.

## Consequences

The kernel gains generally reusable global-name semantics and the process-info
shape required by `proc_lib`. The three declarations have strong differential
and stateful evidence, but remain partial until their full Erlang argument and
failure domains are proved.
