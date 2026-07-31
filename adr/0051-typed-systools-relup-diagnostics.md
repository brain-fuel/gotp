# ADR 0051: Typed systools relup diagnostics

## Status

Accepted, differential evidence incomplete.

## Specification

Pinned OTP `systools_relup:format_error/1` and `format_warning/1` dispatch over
untyped Erlang terms. GoTP instead exposes sealed `RelupError`, `RelupWarning`,
and `FileOperation` alternatives. Exhaustive formatting preserves the pinned
message text, prefix behavior, and newline placement while making unsupported
states unrepresentable for typed callers.

Raw fallback terms use a deterministic Erlang-shaped renderer. Complete `~tp`
parity and execution against the pinned OTP runtime remain required before
either declaration can be conformant.

## Traceability

- Decision: `adr:0051-typed-systools-relup-diagnostics`.
- Pinned source: `OTP-29.0.4:lib/sasl/src/systools_relup.erl#format_error/1`.
- Code: `gotp.otp.systools-relup-diagnostics`.
- Laws: `test:gotp.otp.systools-relup-diagnostic-laws`.
