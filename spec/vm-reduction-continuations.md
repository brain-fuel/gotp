# VM reduction continuation specification

- Artifact: `spec:gotp.vm-reduction-continuations`
- Decision: `adr:gotp.vm-reduction-continuations`
- Deployable unit: `code:gotp.vm.reduction-continuation`
- Law suite: `test:gotp.vm.reduction-continuation-laws`
- Upstream baseline: `OTP-29.0.4@1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Laws

1. A VM reduction budget is strictly positive.
2. Suspension preserves the program counter, registers, stack, and return stack.
3. Partitioning execution into finite positive budgets does not change the
   completed value or total instruction count.
4. Supported local calls and returns consume one reduction at the corresponding
   OTP dispatch boundary.
5. Supported non-dispatch instructions consume no reduction.
6. The instruction step limit applies across all resumed slices.

## Deferred OTP semantics

The implemented cost map covers only the currently executable instruction
subset. External dispatch, BIF and NIF charging, GC work, receive-loop yields,
traps, exceptions, and all unimplemented opcodes remain required before this
capability can become conformant.
