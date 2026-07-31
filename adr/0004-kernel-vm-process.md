# ADR 0004: A VM continuation is a kernel process behavior

- Status: accepted
- Artifact: `adr:gotp.kernel-vm-process`
- Specifies: `spec:gotp.kernel-vm-process`
- Implemented by: `code:gotp.erts.vm-process`
- Verified by: `test:gotp.erts.vm-process-laws`

## Context

The kernel run queue and VM continuation were independently reduction-aware but
did not execute BEAM state as a scheduled process. A bridge must preserve VM
state, process exit semantics, and reduction partition invariance without
introducing a package cycle.

## Decision

The `erts` package owns an adapter that imports both `kernel` and `vm`. Each
kernel behavior invocation resumes one VM reduction. Suspension yields and is
requeued; completion exits with `normal`; VM failure exits with the immutable
term `{gotp_vm_failure, Binary}`. Adapter construction uses `result.Result` and
its externally visible lifecycle is an exhaustive Go+ enum.

## Consequences

Kernel budget partitioning does not change VM results or total dispatch
reductions for the supported instruction subset. BIF messaging, receive state,
exception classes, stack traces, process dictionaries, and exact accounting for
zero-reduction completion and failed instructions remain deferred.
