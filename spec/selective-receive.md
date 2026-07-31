# Selective receive specification

- Artifact: `spec:gotp.selective-receive`
- Decision: `adr:gotp.selective-receive-cursor`
- Deployable units: `code:gotp.vm.host-effects`, `code:gotp.erts.selective-receive`
- Law suites: `test:gotp.vm.selective-receive-laws`, `test:gotp.erts.selective-receive-laws`
- Upstream baseline: `OTP-29.0.4@1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Laws

1. `loop_rec` observes but does not commit the current message.
2. `loop_rec_end` advances the cursor and consumes one reduction.
3. `remove_message` removes only the selected message and resets the cursor.
4. Skipped messages retain their original order.
5. Empty receive reaches `wait` without polling reductions.
6. Delivery wakes a waiting process at its receive-loop continuation.

## Deferred semantics

Receive markers, timeout setup and cancellation, timeout-value exceptions,
tracing tokens, distributed message decoding charges, aliases, and priority
messages remain required for conformance.
