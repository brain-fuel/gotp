# Kernel VM-process specification

- Artifact: `spec:gotp.kernel-vm-process`
- Decision: `adr:gotp.kernel-vm-process`
- Deployable unit: `code:gotp.erts.vm-process`
- Law suite: `test:gotp.erts.vm-process-laws`
- Upstream baseline: `OTP-29.0.4@1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Laws

1. Construction succeeds only for a valid VM continuation and positive quantum.
2. A suspended VM remains runnable with registers, stack, and program counter intact.
3. Kernel slice partitioning does not change the completed VM value.
4. For the supported dispatch-only program subset, kernel and VM reduction totals agree.
5. VM completion produces the process exit reason `normal`.
6. VM failure produces a structured immutable term tagged `gotp_vm_failure`.

## Deferred OTP semantics

The adapter does not yet expose mailbox BIFs, selective receive, exception
classes and stack traces, process dictionaries, timers, external calls, or
accurate zero-reduction and failure accounting. These gaps prevent conformance.
