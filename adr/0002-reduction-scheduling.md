# ADR 0002: Reduction budgets are validated capabilities

- Status: accepted
- Artifact: `adr:gotp.reduction-scheduling`
- Specifies: `spec:gotp.reduction-scheduler`
- Implemented by: `code:gotp.kernel.scheduler`
- Verified by: `test:gotp.kernel.scheduler-laws`

## Context

ERTS schedules runnable processes by reductions rather than wall-clock duration.
An unconstrained integer budget admits zero and negative states that have no
scheduler meaning, while a report containing only counts cannot distinguish
budget exhaustion from system quiescence.

## Decision

GoTP represents a positive reduction budget as an opaque value constructed
through `result.Result`. A scheduler slice returns an exhaustive state:
`SliceExhausted` when runnable work remains after consuming the budget, or
`SliceQuiescent` when no runnable process remains. One cooperative behavior step
currently consumes one reduction.

## Consequences

Budget conservation, round-robin fairness, waiting-process quiescence, and
message wakeup are executable laws. Compatibility remains partial because BEAM
instruction-weighted reductions, priorities, scheduler migration, dirty work,
timer wheels, and SMP behavior are not implemented by this decision.
