# Core term instructions

GoTP executes the foundational OTP-29.0.4 term and control instructions used by real list-processing code.

## Implemented semantics

- Type tests for integers, floats, numbers, atoms, booleans, binaries, bitstrings represented as binaries, tuples, lists, maps, PIDs, ports, and references.
- Empty-list and nonempty-list tests across proper and improper list representations.
- Exact equality and numeric equality without large-integer float rounding.
- Tuple arity, tagged-tuple tests, tuple element extraction, and `put_tuple2`.
- Proper/improper list head/tail extraction and `put_list` construction.
- `select_val` and `select_tuple_arity` with validated key/label pairs and failure labels.
- Register swapping, Y-register initialization, stack trimming, `allocate_heap`, source-line markers, and heap checks.
- Reserved BEAM atom index zero refines to the empty list.

## Runtime memory boundary

Current runtime terms are immutable Go values. `test_heap` therefore discharges without relocation because instruction execution cannot observe a process-heap capacity. This must be replaced by an explicit `ProcessHeap` capacity proof when runtime term residency moves into process arenas.

## Executable evidence

- `gotp.vm.core-term-instructions`
- `gotp.vm.core-term-laws`
- `gotp.erts.pinned-lists-execution-laws`
- Pinned artifact: `beam/testdata/otp-29.0.4/lists.beam`

The pinned law executes OTP `lists:reverse/1` on `[1,2]`, producing `[2,1]` in nine instructions and one reduction. Longer paths currently reach unresolved cross-module/self-export calls.
