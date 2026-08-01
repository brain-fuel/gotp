# Pinned gen_statem static type compatibility

- Specification: `spec:gotp.otp.gen-statem-static-types`
- Parent: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.pinned-gen-statem-static-types`
- Deployable code: `code:gotp.otp.genstatem-types`

The public `goforge.dev/gotp/otp/genstatem` package models all 25 OTP 29.0.4
exported `gen_statem` type declarations as sealed Go+ algebras, generic callback
results, refined structs, and opaque request wrappers. Applications construct
typed values and pass them through total codecs instead of assembling raw
callback tuples.

Canonical codecs cover server names and references, request identifiers and
collections, event types, callback modes, transitions, ordinary and entry-only
actions, replies, start options and results, callback result families, and
formatting status. Single actions accepted by OTP decode to canonical action
lists. Invalid combinations return path-specific failures before VM execution.

The official OTP corpus executes 23 accepted and rejected terms through the
unmodified lifecycle engine. Property laws prove generated callback/action
canonicalization, representative tests cover every type family, compile-fail
fixtures reject ordinary actions in state-entry results and cross-family
callback assignments, and integration laws connect lifecycle, asynchronous
request, and formatting evidence.

All 25 declaration rows are partial. Complete assurance remains open for the
unbounded embedded Erlang term domains, all proc-lib/debug option alternatives,
and exhaustive correspondence to Erlang's static type checker.
