# ADR 0050: Exported function terms use external dispatch

## Status

Accepted.

## Context

OTP modules embed exported function literals such as `fun maps:remove/2`.
Unlike local closures, exported functions have an MFA but no local entry label.
Treating every function term as a local closure attempts to jump to label zero
and bypasses native BIF overrides.

## Decision

`call_fun` and `call_fun2` inspect the function form. Local, old, and new
closures retain module-aware label dispatch and captured environments.
`ExportedFunction` constructs its MFA and uses the same native-first,
linked-BEAM-fallback dispatch contract as `call_ext`. Returned values continue
at the next instruction; raised outcomes enter ordinary exception handling.

## Consequences

Higher-order OTP code can pass exported native functions without wrappers.
Missing exported functions fail as unbound MFAs rather than missing labels.

## Traceability

- Specification: `spec/otp-stdlib-beam-parity.md`
- Source unit: `gotp.vm.function-instructions`
- Laws: `gotp.erts.otp29-maps-differential`,
  `gotp.erts.otp29-maps-callback-differential`
