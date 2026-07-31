# ADR 0003: VM execution is resumable at OTP reduction boundaries

- Status: accepted
- Artifact: `adr:gotp.vm-reduction-continuations`
- Specifies: `spec:gotp.vm-reduction-continuations`
- Implemented by: `code:gotp.vm.reduction-continuation`
- Verified by: `test:gotp.vm.reduction-continuation-laws`

## Context

The reference interpreter previously ran a function until completion or a
safety step limit. ERTS instead preserves execution state and returns to the
scheduler when `FCALLS` reaches zero. In OTP 29.0.4, `DISPATCH`,
`DISPATCH_EXPORT`, `DISPATCH_FUN`, and `DISPATCH_RETURN` decrement that budget.

## Decision

GoTP execution is represented by a `Continuation`. A positive opaque
`VMReductionBudget` is consumed only at dispatch boundaries represented by the
currently supported instruction subset. `ExecutionSlice` exhaustively reports
suspension or completion and includes both reduction and instruction counts.
The independent instruction step limit remains a safety bound.

The reference rules are pinned to OTP commit
`1259612946cb36a8bf9614b289090bb32fbcbeb2`, principally
`erts/emulator/beam/emu/macros.tab` and `instrs.tab`.

## Consequences

Slicing no longer changes program results, and the VM can participate in a
reduction scheduler without restarting execution. Compatibility remains partial:
external calls, BIFs, GC charges, receive-loop yields, traps, exceptions, and
the remainder of the BEAM instruction set are not yet represented.
