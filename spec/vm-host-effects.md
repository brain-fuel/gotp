# VM host-effect specification

- Artifact: `spec:gotp.vm-host-effects`
- Decision: `adr:gotp.explicit-vm-host-effects`
- Deployable units: `code:gotp.vm.host-effects`, `code:gotp.erts.vm-process`
- Law suites: `test:gotp.vm.host-effect-laws`, `test:gotp.erts.message-effect-laws`
- Upstream baseline: `OTP-29.0.4@1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Send laws

1. `send/0` cannot execute without explicit host authority.
2. The destination is read from `x(0)` and the message from `x(1)`.
3. A successful send stores the message in `x(0)`.
4. Send consumes one VM dispatch reduction.
5. ERTS delivery clones the immutable message and wakes a waiting recipient.
6. Sending to a nonexistent local PID still returns the message.

## Deferred semantics

Registered destinations, aliases, ports, remote distribution, tracing tokens,
priority messages, and exact bad-destination exception classes remain required.
