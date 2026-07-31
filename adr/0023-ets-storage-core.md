# ADR 0023: ETS keys arbitrary BEAM terms without Go map identity

## Status

Accepted.

## Context

BEAM terms include lists, maps, binaries, tuples, and other values that cannot
all be Go map keys. Using interface identity would violate Erlang equality and
make ordered-set behavior dependent on host representation.

## Decision

The first ETS storage core keeps cloned tuple objects in table-owned slices.
Set, bag, and duplicate-bag keys use exact term equality. Ordered-set keys use
the GoTP total-term comparator and maintain deterministic order. Registry and
table locks separate identity/lifecycle mutation from object mutation.

Table kind, access mode, mutation outcome, and failure rails are sealed Go+
enums. Lookup and name resolution use `std/result` and `std/option`; missing or
unauthorized state is never encoded as a nil term.

Predicate-plus-mutation operations (`insert_new` and `take`) execute beneath one
table write lock. They are primitives rather than compositions of exported
lookup and insert/delete operations, so their OTP atomicity does not depend on
caller discipline.

Traversal exposes a sealed key-or-end state rather than the OTP wire atom
`$end_of_table`; the later BIF adapter owns that representation conversion.
Absent-key navigation is defined only for ordered sets and uses the same total
term comparator as storage ordering.

Counter operations are a sealed add-or-threshold enum and retain arbitrary
precision through `big.Int` copies. The implementation validates every operand
before replacing the tuple under the table write lock, preserving OTP atomicity
and preventing failed operations from partially updating state.

Object patterns compile once into a sealed recursive Go+ enum. Constants are
cloned, variable identities are numeric and deterministically sorted, and
repeated occurrences unify through exact term equality. Pattern deletion holds
the table write lock for the complete scan, preserving atomic visibility.

Match specifications compile into sealed operator and expression enums before
execution. Unknown operators, wrong arities, and variables absent from the head
are typed compile failures. Select variants share one evaluator, while count and
delete require a boolean `true` result as OTP specifies.

Limited selection uses immutable cloned snapshots. Continuations never hold a
table lock and resumption returns a new continuation, making replay deterministic
and preventing continuation consumers from mutating ETS storage through shared
term backing data.

## Consequences

This representation prioritizes semantic correctness and arbitrary-term safety
over the eventual OTP performance target. A later indexed representation may
replace slices only if differential laws preserve equality, multiplicity,
ordering, access, and lifecycle behavior.

## Traceability

- Parent specification: `spec/ets.md`
- Compatibility item: `stdlib.ets`
- Source unit: `gotp.otp.ets-core`
- Laws: `gotp.otp.ets-core-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, `stdlib/ets`
