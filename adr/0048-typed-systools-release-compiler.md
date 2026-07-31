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
- Laws: `test:gotp.otp.systools-rc-laws`.

## Remaining obligations

The raw Erlang high-level instruction vocabulary still needs a total decoder
into the sealed Go+ representation. Exact OTP SCC condensation ordering,
instruction syntax diagnostics, `mnesia_backup`, legacy restart aliases, and a
differential corpus against `systools_rc:translate_scripts/4` remain open.
Consequently this ADR does not establish declaration or module conformance.
