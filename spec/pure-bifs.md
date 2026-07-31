# Pure BIF execution

## Instruction contract

`bif0..2` and `gc_bif1..3` resolve their BIF operand through the active module's
import table. The imported arity must equal the instruction shape. Every source
operand is resolved before invoking the explicit runtime-native capability.

A returned value is assigned to the destination and execution advances. A
rejection branches to a nonzero failure label. An unbound BIF, missing capability,
zero failure label, malformed live count, malformed import, or arity mismatch is
a deterministic VM failure.

These instructions consume no scheduler reduction independently; dispatching
calls and returns continues to follow pinned OTP 29 reduction classes.

## Pure registry contract

The default OTP call registry includes:

- `erlang:++/2`, `--/2`, and `length/1`
- `erlang:+/2`, `-/2`, `*/2`, and `div/2`
- `erlang:=:=/2`
- `erlang:integer_to_list/1`, `float_to_list/1`, and `atom_to_list/1`
- `erlang:element/2` and `setelement/3`
- `lists:reverse/2`

Invalid operands reject with `badarg` or `badarith`. Integer arithmetic is
arbitrary precision. List append accepts any right tail and list subtraction
requires proper lists. Tuple positions are one-based.

## Evidence

Shrinking properties cover integer arithmetic round trips and list-append
associativity. Synthetic VM laws cover encoded failure branching. Pinned OTP 29
`lists.beam` laws execute `lists:sum/1`, `lists:append/2`, and `lists:reverse/1`
through the decoder, interpreter, and runtime registry.

## Decision

See ADR `0014-pure-otp-bifs-and-bif-opcodes`.
