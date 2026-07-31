# ADR 0015: One checked Erlang total order for terms and VM tests

## Status

Accepted.

## Context

BEAM comparison-test instructions such as `is_lt` and `is_ge` are used for
ordinary control flow, not only sorting. Pinned OTP 29 `lists:seq/2`,
`duplicate/2`, `nth/2`, `min/1`, and `max/1` all depend on them. Implementing
integer-only instruction special cases would disagree with Erlang's cross-kind
total order and duplicate semantics across the VM and runtime libraries.

## Decision

The immutable term package owns a checked `Compare` relation with a sealed Go+
`Ordering` result. It implements numeric comparison, atom order, references,
ports, PIDs, tuple arity and lexical order, map size/key/value order, the empty
list boundary, proper and improper lexical list order, and binary byte order.
Invalid terms and NaN produce explicit order failures.

Numerically equal integers and floats compare equal for relational operators;
map-key sorting applies an exact integer-before-float tie break because map keys
remain exact terms. VM `is_lt` and `is_ge` resolve operands, call this relation,
and either advance or jump to their encoded failure label.

The order covers every term kind currently represented by GoTP. Local funs were
added under ADR 0018 and occupy the required position between references and
ports. External fun encoding and creator-process identity remain incomplete, so
full OTP total-order parity must not be claimed from these laws.

## Traceability

- Specification: `spec/term-order.md`
- Source units: `gotp.term.total-order`, `gotp.vm.term-order-tests`
- Laws: `gotp.term.total-order-laws`, `gotp.erts.pinned-otp-lists-laws`
