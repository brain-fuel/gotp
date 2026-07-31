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
- Differential law: `test:gotp.otp.systools-relup-otp29-differential`.
- Oracle: official `erlang:29.0.4-alpine` image at manifest digest
  `sha256:a6e2d0c34adb0038f98953d89d82a501a26b8905027a8e840bf8851531de75d8`.
- Corpus: `otp/release/testdata/otp-29.0.4-systools-relup.corpus` at
  `sha256:077d7cb7a3ec3df4f9addaf269e31606a0874906289464277b66453d92af3bd7`.

## Remaining obligations

This decision does not claim `systools_relup` parity. The `systools_rc`
high-level dependency graph and low-level translation, release/application file
discovery, warning compatibility, pre-R15 SASL handling, canonical Erlang-term
serialization, and complete Erlang regular-expression compatibility remain
open. The checked-in corpus proves exact/regex ordering, whole-match behavior,
Unicode versions, malformed-entry skipping, invalid-regex failure, and misses.
