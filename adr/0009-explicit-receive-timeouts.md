# ADR 0009: Model receive timeouts as explicit capabilities

## Status

Accepted

## Context

BEAM receive timeouts combine mailbox cursor state, scheduler wakeups, cancellation races, and time. Reading wall time in the VM or mutating a process from a timer callback would make replay, proof, and race analysis depend on ambient effects.

## Decision

The VM accepts a closed timer capability with wait, cancel, and finish effects. The ERTS adapter owns the active kernel timer and injects a `goplus/std/clock.Clock`. Kernel timer handles expose exhaustive pending, fired, and cancelled states. Callback execution may only transition the synchronized timer handle and enqueue a PID; scheduler-owned process state remains single-writer.

`wait_timeout` validates and bounds milliseconds before creating a duration. The adapter starts a finite timer once, distinguishes message wakeup from expiry through the handle state, cancels on message removal, and resets the receive cursor on `timeout`.

## Consequences

Fake clocks prove deadline behavior without sleeps. Production uses `clock.Real`. Hosts that do not grant timer authority cannot execute finite receive timeouts. Existing non-timed messaging constructors remain source-compatible.

## Traceability

- Specification: `spec/receive-timeout.md`
- VM law: `gotp.vm.receive-timeout-laws`
- ERTS law: `gotp.erts.receive-timeout-laws`
- Kernel law: `gotp.kernel.timer-wakeup-laws`
