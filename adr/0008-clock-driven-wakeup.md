# ADR 0008: Timer callbacks enqueue wakeups, never mutate run queues

- Status: accepted
- Artifact: `adr:gotp.clock-driven-wakeup`
- Specifies: `spec:gotp.clock-driven-wakeup`
- Implemented by: `code:gotp.kernel.timer-wakeup`
- Verified by: `test:gotp.kernel.timer-wakeup-laws`

## Context

`std/clock` callbacks may run concurrently under the real clock. The kernel run
queue is scheduler-owned and cannot be mutated safely by timer goroutines.
Polling the clock would be deterministic but would not provide real wakeup.

## Decision

Timer callbacks append PIDs to a mutex-protected pending queue. `Kernel.Run`
drains that queue and performs the state transition to runnable. Timer creation
requires an explicit `clock.Clock`, validates the target and delay, and returns
the standard cancellable `clock.Stop` capability.

## Consequences

Fake-clock tests require no sleeps and real timer callbacks do not race on
process or run-queue state. A scheduler invocation is still required to drain a
fired wakeup; the future long-running scheduler loop will provide that service.
