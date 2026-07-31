# Public native macros are compiler-profiled compatibility obligations

- ADR: `adr:gotp.pinned-native-api-macros`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-native-macros`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Parse macro declarations from the eight canonical OTP NIF, driver, shared,
configuration, Windows dynamic-driver, and EI headers. Intersect those names
with the active `-dM` output of each pinned profile compiler. This excludes
system and compiler macros while preserving target conditionals, replacement
tokens, object/function form, arity, variadic state, source ownership, and
surface provenance.

Qualify identities by `darwin-arm64-lp64`, `linux-amd64-lp64`,
`linux-arm64-lp64`, or `windows-amd64-llp64`. Include observable guards and
compatibility aliases rather than guessing which documented consumers rely on
them. Keep every discovered item missing until behavioral or differential
evidence proves its GoTP implementation.

## Consequences

The ledger gains 1,047 profile-qualified requirements: 186 for each POSIX
profile and 489 for Windows. Compiler builtins cannot enter the inventory
unless an OTP-owned canonical header declares the same name. The global
inventory remains incomplete because macro coverage expands native syntax but
does not establish runtime or application behavior.

## Evidence

`test:gotp.compat.otp-native-macro-laws` proves source ownership, profile pins,
object/function partitioning, conditional activation, continuation and
variadic normalization, strict ordering, complete ledger coverage, and parser
totality over arbitrary bytes.
