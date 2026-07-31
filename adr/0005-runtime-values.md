# ADR 0005: Instruction operands and runtime terms are distinct

- Status: accepted
- Artifact: `adr:gotp.runtime-values`
- Specifies: `spec:gotp.runtime-values`
- Implemented by: `code:gotp.vm.runtime-values`
- Verified by: `test:gotp.vm.runtime-value-laws`

## Context

BEAM operands encode register locations, labels, and indexes into atom and
literal tables. They are not Erlang runtime values. Storing operands in X/Y
registers made PIDs, tuples, binaries, maps, and references impossible and
would make message effects semantically incorrect.

## Decision

Machine registers and execution results contain immutable `term.Term` values.
Instruction operands remain `beam.Operand` and are resolved at execution time.
Atom and literal indexes use explicit immutable pools keyed by their encoded
index. Register and pool boundaries clone terms to preserve ownership.

## Consequences

VM registers can now carry the complete GoTP term algebra, including PIDs needed
for send and receive. Module atom/literal loading and the remaining operand
forms still require integration before full instruction compatibility.
