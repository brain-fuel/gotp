# ADR 0048: Typed systools release compiler

## Status

Accepted, incomplete compatibility slice.

## Specification

OTP `OTP-29.0.4` artifact `systools_rc:translate_scripts/4` is the reference.
Artifact `gotp.otp.systools-rc` compiles sealed high-level release instructions
into artifact `gotp.otp.release-script`, which is directly executable by the
transactional release runtime.

The compiler expands application add/remove/restart instructions, validates
unique module definitions and dependency closure, groups related module
operations, emits object-code staging, balances suspend/resume operations,
orders upgrade and downgrade loads and code changes separately, merges staging
by application/version, and canonicalizes emulator restart placement. Every
failure is a sealed value and no translation effect has ambient authority.

## Traceability

- Specification: OTP `systools_rc.erl` at pinned tag `OTP-29.0.4`.
- Decision: `adr:0048-typed-systools-release-compiler`.
- Code: `gotp.otp.systools-rc`, `gotp.otp.release-script`.
- Laws: `test:gotp.otp.systools-rc-laws`,
  `test:gotp.otp.systools-rc-parser-laws`.

## Remaining obligations

Artifact `gotp.otp.systools-rc-parser` now totally decodes the documented raw
Erlang high-level vocabulary, normalizes shorthand forms, preserves per-script
commit boundaries, and connects relup deltas directly to the compiler. Exact
OTP SCC condensation ordering, diagnostic text, the pinned-but-unimplemented
`mnesia_backup` operation, unresolved legacy restart aliases, and a
differential corpus against `systools_rc:translate_scripts/4` remain open.
Consequently this ADR does not establish declaration or module conformance.
