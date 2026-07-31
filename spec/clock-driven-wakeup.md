# Clock-driven wakeup specification

- Artifact: `spec:gotp.clock-driven-wakeup`
- Decision: `adr:gotp.clock-driven-wakeup`
- Deployable unit: `code:gotp.kernel.timer-wakeup`
- Law suite: `test:gotp.kernel.timer-wakeup-laws`

## Laws

1. Timer creation requires an explicit non-nil `clock.Clock` capability.
2. Negative delays and nonexistent target processes are rejected.
3. A process cannot wake before its deadline.
4. A fired timer makes a live waiting process runnable at the next scheduler drain.
5. Cancelling a pending timer prevents wakeup.
6. Timer callbacks never mutate process or run-queue state directly.

## Deferred semantics

VM receive timeout continuations, timeout cancellation on message selection,
timer wheels, process timer BIFs, monotonic-time correction, and scheduler-loop
notification remain required for OTP conformance.
