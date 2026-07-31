# Runtime value specification

- Artifact: `spec:gotp.runtime-values`
- Decision: `adr:gotp.runtime-values`
- Deployable unit: `code:gotp.vm.runtime-values`
- Law suite: `test:gotp.vm.runtime-value-laws`

## Laws

1. Instruction locations and labels never inhabit runtime registers.
2. Runtime registers hold immutable Erlang terms.
3. Register reads and writes preserve structural term equality without aliasing mutable storage.
4. Integer and character operands materialize as integer terms.
5. Atom and literal operands resolve only through explicit encoded-index pools.
6. Missing pool entries are typed VM failures.

## Deferred semantics

Module construction must populate exact atom and literal pools from BEAM chunks.
External function identifiers, funs, catches, and continuation pointers require
their own typed runtime representations rather than overloading Erlang terms.
