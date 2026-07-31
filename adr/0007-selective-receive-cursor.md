# ADR 0007: Selective receive owns a persistent cursor

- Status: accepted
- Artifact: `adr:gotp.selective-receive-cursor`
- Specifies: `spec:gotp.selective-receive`
- Implemented by: `code:gotp.erts.selective-receive`
- Verified by: `test:gotp.erts.selective-receive-laws`, `test:gotp.vm.selective-receive-laws`

## Context

OTP receive does not remove a message until a clause matches. `loop_rec_end`
advances a save pointer, while `remove_message` commits the selected message.
A destructive receive API alone cannot preserve skipped-message order.

## Decision

VM receive authority is an exhaustive peek/advance/remove capability. The ERTS
adapter persists pulled message envelopes and a cursor across scheduler slices.
`loop_rec` peeks, `loop_rec_end` advances and consumes one reduction,
`remove_message` commits and resets the cursor, and `wait` returns an explicit
waiting execution state.

## Consequences

Skipped messages remain ordered and waiting VM processes wake on delivery.
Buffered envelopes temporarily live in the adapter rather than the kernel
mailbox count. Receive markers, tracing tokens, distribution decode costs,
timeouts, aliases, and priority messages remain deferred.
