# Runtime tracing foundation

- Decision: `adr:gotp.runtime-tracing-foundation`
- Deployable unit: `code:gotp.kernel.runtime-tracing`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Events

The kernel emits sealed events for process spawn and scheduling, link and
monitor creation, queued user/exit/down signals, and process exit. Each enabled
tracer assigns a monotonic sequence number at observation time.

## Capacity and ownership

Tracing is an explicit kernel capability and is disabled by default. Enabling
requires a positive bounded capacity. Once full, the tracer retains the newest
records while sequence numbers remain monotonic. Term-bearing events are cloned
on record and snapshot, preventing observers from mutating runtime state.

## Incomplete boundary

Per-process and per-event filters, trace sessions, call/return tracing, match
specifications, timestamps, ports, scheduler wall time, profiling, distributed
tracing, crash dumps, and OTP trace protocol compatibility remain required.

## Evidence

`test:gotp.kernel.runtime-tracing-laws` covers event ordering, process identity,
term cloning, bounded retention, and capability disablement.
