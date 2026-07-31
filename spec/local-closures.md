# Local closures

## Function table

`DecodeModuleFunctions` decodes the `FunT` count and six-word entries:
function atom, visible arity, label, index, free-value count, and unique value.
Malformed shape, count limits, free-value limits, and atom references return
typed failures. A missing `FunT` chunk yields an empty table.

## Term contract

A local fun is an immutable term containing its module and function-table
identity plus a cloned captured environment. Projection and cloning never expose
the stored environment slice. Exact equality compares identity and captures.
Term order places funs after references and before ports.

## Opcode contract

`make_fun3 Index Destination Captures` requires a known template and exactly its
declared free-value count. Every capture is resolved and cloned before the fun is
assigned.

`call_fun Arity` reads the fun from `X[Arity]`. `call_fun2 Tag Arity Fun` resolves
the explicit fun operand. Both require matching visible arity and a linked module
and label. Captures are copied into X registers beginning at `X[Arity]`; caller
module and next instruction are saved before transfer.

`is_function` tests kind. `is_function2` additionally tests visible arity. A
failed test jumps to its encoded failure label.

## Evidence

Pinned OTP 29 `lists.beam` proves the `thing_to_list/1` FunT entry and executes
`lists:concat/1` through `make_fun3`, `is_function2`, `call_fun2`, conversion
BIFs, and module-aware return. A synthetic VM law proves non-empty environment
capture and `call_fun` restoration. Term laws prove environment immutability.

## Decision

See ADR `0018-local-closure-terms-and-dispatch`.
