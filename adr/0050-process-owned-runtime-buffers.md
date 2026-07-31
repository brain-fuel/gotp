# ADR 0050: Process-owned runtime buffers

## Status

Accepted, incomplete ERTS process-memory slice.

## Specification

Byte arenas cannot safely own Go pointer-bearing `term.Term` values without
serialization. Go+ std artifact `goplus.std.memory-buffer` therefore provides a
typed ownership group for runtime slices. Removal clears vacated slots, reset
clears GC-visible references while retaining capacity, and release clears and
drops the complete backing allocation.

GoTP artifacts `gotp.erts.vm-process` and `gotp.vm.register-memory` use this
buffer for selective-receive message fragments and X/Y registers. Live
processes preserve ordering, cursor, and reverse Y-index semantics. Frame
deallocation clears removed Y slots. Completion and uncaught exception clear X
terms and drop Y and message backing storage; hard VM failures invoke the same
continuation release capability.

Return PC, module image, and code-leave capability now form one typed return
frame instead of three parallel slices. Return and exception stacks use typed
buffers; unwind truncation clears discarded frames, handlers, pending exception
terms, and callbacks. Terminal release invokes code-leave capabilities in
reverse stack order exactly once before dropping both stack allocations.

Kernel process mailboxes, the scheduler run queue, and staged remote signals
also use typed buffers. Selective receive and round-robin scheduling retain
their existing order laws. Process termination releases mailbox backing
storage, while scheduler-owned run and remote-signal queues reset cleared slots
and retain capacity for reuse.

## Traceability

- Decision: `adr:0050-process-owned-runtime-buffers`.
- Std code: `goplus.std.memory-buffer`.
- Std laws: `test:goplus.std.memory-buffer-laws`.
- Consumer code: `gotp.erts.vm-process`.
- Consumer laws: `test:gotp.erts.selective-receive-laws`.
- VM laws: `test:gotp.vm.register-memory-laws`.
- Stack laws: `test:gotp.vm.stack-memory-laws`.
- Kernel queue laws: `test:gotp.kernel.queue-memory-laws`.

## Remaining obligations

Process heap term storage, off-heap binaries, and scheduler-local caches other
than the run and remote-signal queues still use ordinary Go allocations. This
decision does not establish ERTS process-memory parity.
