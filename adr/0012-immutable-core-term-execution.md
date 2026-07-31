# ADR 0012: Execute core BEAM terms through immutable refinements

## Status

Accepted

## Context

Real BEAM code relies on compact fail-label tests and destructive-looking list/tuple instructions. Implementing these with unchecked casts or mutable shared containers would break process isolation and make malformed bytecode capable of panicking the runtime.

## Decision

Core instructions exhaustively match the closed `term.Term` and `term.Kind` sums. Reads resolve through checked operands; writes clone through machine assignment. Proper and improper list tails are reconstructed explicitly. Selection tables validate alternating key/label shapes before control transfer.

Numeric equality compares mixed integers and floats as exact rationals, avoiding precision loss for integers beyond IEEE-754 exact range. Reserved atom index zero maps to the BEAM empty-list value.

Heap checks are reduction-free and observationally quiescent while terms remain immutable Go values. The specification records the required replacement when process-arena residency is connected to the VM.

## Consequences

Malformed operand shapes, invalid registers, missing labels, empty-list decomposition, and tuple bounds fail structurally. Real OTP list code can execute without converting runtime terms back into encoded operands.

Ordering comparisons, maps, funs, BIF instruction families, exceptions, and cross-module continuations remain separate work.

## Traceability

- Specification: `spec/core-term-instructions.md`
- Code artifact: `gotp.vm.core-term-instructions`
- Property law: `gotp.vm.core-term-laws`
- Pinned artifact law: `gotp.erts.pinned-lists-execution-laws`
