# Reduction scheduler specification

- Artifact: `spec:gotp.reduction-scheduler`
- Decision: `adr:gotp.reduction-scheduling`
- Deployable unit: `code:gotp.kernel.scheduler`
- Law suite: `test:gotp.kernel.scheduler-laws`
- Upstream baseline: `OTP-29.0.4@1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Laws

1. A reduction budget is strictly positive.
2. A non-quiescent slice consumes exactly its budget.
3. Runnable processes are selected round-robin; after any finite slice their
   reduction counts differ by at most one when all continuously yield.
4. A waiting process consumes no reductions after entering the waiting state.
5. Delivery to a waiting process makes it runnable without polling.
6. Exhaustion and quiescence are distinct exhaustive outcomes.

## Deferred OTP semantics

This slice does not claim full ERTS scheduler compatibility. Instruction and
BIF reduction weights, priority queues, work stealing, scheduler migration,
dirty CPU and I/O schedulers, timer wheels, and SMP ordering remain required.
