# Distribution dispatch exposes exact and deferred kernel outcomes

- ADR: `adr:gotp.distribution-kernel-dispatch`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable units: `code:gotp.erts.distribution-dispatch`, `code:gotp.kernel.remote-monitor-signals`, `code:gotp.kernel.remote-process-signals`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Dispatch validated controls through an ERTS boundary into kernel operations.
Add kernel primitives for remote links and monitors, caller-supplied local
monitor references, remote DOWN delivery, and an ordered outbound remote-signal
queue. Preserve existing local monitor construction by delegating it to the
explicit-reference primitive.

Return a closed outcome distinguishing applied, missing destination, required
reply, and deferred semantics. Exact dispatch covers PID send, remote link,
exit, remote monitor, remote demonitor, DOWN, alias send, and remote unlink.
Local termination emits ordered outbound EXIT/DOWN signals for remote
relationships. `UNLINK_ID` removes the link
and returns the mandatory reversed-endpoint `UNLINK_ID_ACK` before subsequent
caller-managed output.

## Consequences

No unsupported control is silently approximated. Registered sends, node links,
group leaders, seq-trace variants, remote spawn, named monitor installation,
transport draining, and outstanding local unlink acknowledgement state remain explicit deferred
work. Kernel mutation remains scheduler-serialized by its caller.

## Evidence

`test:gotp.erts.distribution-dispatch-laws` observes real mailbox, link, process,
monitor, DOWN, alias, missing-destination, reply, and deferred kernel state.
