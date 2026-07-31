# ADR 0022: Process signals remain typed until mailbox observation

## Status

Accepted.

## Context

Links and monitors existed as kernel graph operations, but external exit signals
lacked sender-aware OTP semantics and VM receive could observe only user
messages. Supervisors could consume internal signal variants while ordinary
BEAM processes could not receive trapped exits or monitor notifications.

## Decision

The kernel retains user, exit, and down signals as a sealed Go+ enum while they
are ordered, queued, selected, or flushed. Conversion to OTP tuples happens only
at the ordinary-message receive boundary. Explicit exit is a capability on a
running context and records the sender. `kill` bypasses `trap_exit` and becomes
`killed`; `normal` from another process is ignored by a non-trapping receiver.

This keeps demonitor flushing and signal ordering structural rather than
dependent on tuple inspection, while presenting standard mailbox terms to BEAM
code.

Process aliases are references indexed by the kernel and owned by a process.
Termination removes an owner's aliases as a group. Alias sends enter the same
typed signal queue as PID sends without exposing process state.

Contextual OTP BIFs remain outside the immutable pure-call registry. The ERTS
adapter grants them through the VM's existing external-call capability and the
running process context. This prevents `alias/0` from becoming an ambient
kernel operation while avoiding a parallel effect system.

## Traceability

- Parent specification: `spec/process-signals.md`
- Compatibility item: `runtime.signals`
- Source unit: `gotp.kernel.process-signals`
- Alias source unit: `gotp.kernel.process-aliases`
- Contextual source unit: `gotp.erts.otp-context-bifs`
- Laws: `gotp.kernel.process-signal-laws`
- Alias laws: `gotp.kernel.process-alias-laws`
- BEAM alias laws: `gotp.erts.otp-alias-laws`
- Reference: Erlang/OTP `OTP-29.0.4` process reference manual
