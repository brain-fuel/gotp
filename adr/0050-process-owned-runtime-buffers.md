# ADR 0050: Process-owned runtime buffers

## Status

Accepted, incomplete ERTS process-memory slice.

## Specification

Byte arenas cannot safely own Go pointer-bearing `term.Term` values without
serialization. Go+ std artifact `goplus.std.memory-buffer` therefore provides a
typed ownership group for runtime slices. Removal clears vacated slots, reset
clears GC-visible references while retaining capacity, and release clears and
drops the complete backing allocation.

GoTP artifact `gotp.erts.vm-process` uses this buffer for selective-receive
message fragments. Live processes preserve ordering and cursor semantics.
Completion, uncaught exception, and VM failure release all buffered envelopes
so terminated processes do not retain message term graphs.

## Traceability

- Decision: `adr:0050-process-owned-runtime-buffers`.
- Std code: `goplus.std.memory-buffer`.
- Std laws: `test:goplus.std.memory-buffer-laws`.
- Consumer code: `gotp.erts.vm-process`.
- Consumer laws: `test:gotp.erts.selective-receive-laws`.

## Remaining obligations

X/Y registers, continuation return stacks, exception stacks, process heap term
storage, kernel signal queues, off-heap binaries, and scheduler-local caches
still use ordinary Go allocations. This decision does not establish ERTS
process-memory parity.
