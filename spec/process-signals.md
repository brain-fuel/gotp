# Process signal semantics

- Decision: `adr:gotp.process-signal-semantics`
- Deployable unit: `code:gotp.kernel.process-signals`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Exit signals

An explicit exit signal records sender and target. `kill` is untrappable and
terminates the receiver with reason `killed`. A `normal` signal sent by another
process does not terminate a receiver that does not trap exits. Other reasons
terminate a non-trapping receiver. A trapping receiver gets
`{'EXIT', From, Reason}` as an ordinary mailbox term.

Linked-process termination uses the same typed signal queue and preserves
per-sender ordering. A normal linked termination is ignored by a non-trapping
peer and delivered to a trapping peer.

## Monitor signals

Monitor termination is observable as
`{'DOWN', Reference, process, Target, Reason}` through ordinary receive. The
kernel retains typed `DownSignal` values internally so demonitor-with-flush can
remove an undelivered notification without parsing terms.

## Process aliases

An alias is a kernel-unique reference owned by one live process. Sending to the
reference follows the ordinary ordered user-signal path and preserves sender
identity. Only the owner can revoke it. Owner termination revokes every alias
as a group before any later send can resolve it.

BEAM code creates and revokes aliases through contextual `erlang:alias/0` and
`erlang:unalias/1` calls. These calls are handled by the ERTS process adapter,
not the pure call registry, because alias ownership is a process capability.
The VM send effect accepts either a PID or an alias reference and delegates both
through the current process context.

## Incomplete boundary

Remote aliases and signals, priority signals, asynchronous unlink
acknowledgments, and the complete distribution ordering model remain required
for parity.

## Evidence

`test:gotp.kernel.process-signal-laws` proves untrappable kill translation,
normal-signal immunity, trapped-exit tuple shape, and monitor tuple shape.
`test:gotp.kernel.process-alias-laws` proves routing, sender preservation,
owner-only revocation, and grouped cleanup on owner exit.
`test:gotp.erts.otp-alias-laws` proves BEAM alias creation, reference-target
send, scheduler wakeup, and ordinary receive end to end.
