# ETS semantic storage core

- Decision: `adr:gotp.ets-storage-core`
- Deployable unit: `code:gotp.otp.ets-core`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Tables

The registry creates anonymous or named tables owned by a process. Table IDs
are monotonic opaque values. Names are unique among live tables. Owner exit
deletes every owned table and releases its names as one lifecycle operation.

Tables use one-based configurable tuple keys and support `set`, `ordered_set`,
`bag`, and `duplicate_bag`. Set insertion replaces the object at an equal key.
Bag insertion suppresses an exactly equal object while duplicate-bag insertion
preserves every copy. Ordered-set keys use Erlang total-term comparison and
objects are traversed deterministically in key order.

`insert_new` holds the table write lock across key absence testing and insertion
and therefore admits at most one concurrent winner. `take` returns clones of
every object at a key and removes them in the same transaction. `delete_object`
removes every object exactly equal to its argument while preserving other
objects sharing the key.

`first`, `last`, `next`, and `prev` return a sealed key-or-end traversal state.
Ordered-set navigation follows total term order and accepts an absent probe,
returning its nearest greater or lesser key. Unordered table navigation requires
an existing exact probe key; traversal order is stable but intentionally not a
semantic ordering guarantee.

`update_counter` supports arbitrary-precision add and directional
threshold/set operations on non-key tuple fields in set and ordered-set tables.
Validation and update occur beneath one write lock. Bag tables, missing keys,
key-field updates, invalid positions, and non-integer values fail without
mutating the object.

## Object patterns

OTP object patterns compile into a sealed tree of wildcard, numbered variable,
constant, tuple, and proper-list nodes. Repeated variables unify by exact BEAM
term equality. Captures are returned in numeric variable order. `match_object`
returns cloned source objects, `match` returns capture vectors, and
`match_delete` scans and removes under one table write lock.

Match specifications compile clause heads, guard expressions, and body
expressions before table access. The initial guard core supports exact/loose
equality, total-order comparisons, boolean composition, and atom/integer/number/
tuple/list predicates. Bodies support constants, numbered variables, `$_`, and
`$$`. `select`, `select_count`, and `select_delete` share this evaluator;
deletion holds one write lock for the complete scan.

Limited select returns a sealed complete-or-more page. Its opaque continuation
owns a cloned snapshot, offset, and positive limit. Resume is immutable: the
same continuation can be replayed and produces the same page without retaining
a table lock or observing later table mutation. Concatenating all pages equals
the unlimited selection at snapshot time.

## Access and concurrency

Public tables allow all reads and writes. Protected tables allow all reads but
only owner writes. Private tables allow only owner access. Registry and table
state use separate locks; returned terms are clones, so callers cannot mutate
stored values outside a table operation.

## Incomplete boundary

Remaining match-spec operators/actions, repairable/live select continuations, heirs, ownership transfer, table
fixation, counters, compressed storage, concurrency tuning flags, DETS/file
interop, distributed ownership, and the remaining ETS API remain required.

## Evidence

`test:gotp.otp.ets-core-laws` covers set replacement, bag multiplicity,
ordered-set and unordered navigation, atomic counters/insertion/take, exact-object deletion, access
rights, named lookup, and owner cleanup.
`test:gotp.otp.ets-object-pattern-laws` covers nested patterns, wildcard matching,
numeric capture order, repeated-variable unification, and atomic deletion.
`test:gotp.otp.ets-match-spec-laws` covers guard filtering, special body values,
count/delete behavior, operator validation, and variable-scope validation.
The same laws cover limited-page equivalence, continuation replay, and limit
validation.
