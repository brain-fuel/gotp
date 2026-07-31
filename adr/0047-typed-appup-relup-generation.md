# ADR 0047: Typed appup selection and relup generation

## Status

Accepted, incomplete compatibility slice.

## Specification

OTP `OTP-29.0.4` artifacts `systools_relup:appup_search_for_version/2` and
`systools_relup:mk_relup/4` define the reference behavior. Artifact
`gotp.otp.appup` parses ordered version-script tables into sealed selectors and
artifact `gotp.otp.relup-delta` assembles release deltas.

Exact selectors and binary regular-expression selectors retain source order.
A regular expression selects only when its first match equals the complete base
version. Upgrade and downgrade tables remain distinct. Release deltas retain
top-release order for changed applications, destination order for added
applications, and source order for removed applications. An ERTS-version change
prepends `restart_new_emulator`; the explicit restart option appends
`restart_emulator`.

Malformed terms, invalid regular expressions, duplicate applications, missing
appups, and missing version scripts are typed failures. Returned instruction
terms are cloned so callers cannot mutate parsed specifications.

## Traceability

- Specification: OTP `systools_relup.erl` at pinned tag `OTP-29.0.4`.
- Decision: `adr:0047-typed-appup-relup-generation`.
- Code: `gotp.otp.appup`, `gotp.otp.relup-delta`.
- Laws: `test:gotp.otp.appup-laws`, `test:gotp.otp.relup-delta-laws`.

## Remaining obligations

This decision does not claim `systools_relup` parity. The `systools_rc`
high-level dependency graph and low-level translation, release/application file
discovery, warning compatibility, pre-R15 SASL handling, canonical Erlang-term
serialization, and differential execution against OTP remain open.
