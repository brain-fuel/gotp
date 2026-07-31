# Registered process identity belongs to the kernel

- ADR: `adr:gotp.registered-process-identity`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable unit: `code:gotp.kernel.registered-processes`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Own registered names in the kernel as a bijection between validated atom names
and live local processes. A process has at most one name, a name has at most one
process, and process exit releases its name before propagating signals.

Resolve registered distribution sends and named remote monitors through that
registry. Preserve the monitored name in a distinct sealed DOWN signal and in
outbound remote DOWN state even if the process later exits. Store group-leader
identity per process and permit a valid remote leader for a live local member.

## Consequences

Distribution and local runtime code share one identity authority. Missing named
monitors produce immediate `noproc` DOWN and name reuse after exit cannot alter
an existing monitor's source identity. Local registered BIF adapters, node-link
semantics, seq-trace, remote spawn, and transport draining remain incomplete.

## Evidence

`test:gotp.erts.distribution-dispatch-laws` covers uniqueness, exit cleanup,
registered delivery, named monitor identity, immediate missing-name DOWN, and
remote group leaders.
