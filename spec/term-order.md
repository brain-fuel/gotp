# Erlang term ordering

## Represented order

For the term kinds GoTP currently represents, ascending order is:

1. Numbers
2. Atoms
3. References
4. Funs
5. Ports
6. PIDs
7. Tuples
8. Maps
9. The empty list
10. Non-empty lists
11. Binaries

Local fun identity includes module, function-table identity, and captured
environment. External fun encoding and creator-process identity remain partial.

Numbers compare by numeric value, including exact integer-to-float comparison
through rational conversion. Tuples compare arity before elements. Maps compare
size, ordered exact keys, then corresponding values. Lists compare recursively
across proper and improper tails. Binaries compare bytes lexicographically.

Invalid terms and NaN are not ordered and return a typed failure.

## VM tests

`is_lt Fail Left Right` advances only when `Left < Right`; otherwise it jumps to
`Fail`. `is_ge` advances for equal or greater values and otherwise jumps. Operand
resolution or ordering failure is a deterministic VM failure.

## Evidence

Shrinking laws establish integer antisymmetry and transitivity and list-prefix
lexicographic behavior. A kind-chain law covers the represented cross-kind
order. Pinned OTP 29 `lists.beam` executes `seq/2`, `duplicate/2`, `nth/2`,
`min/1`, and `max/1` through these instructions.

## Decision

See ADR `0015-erlang-total-term-order`.
