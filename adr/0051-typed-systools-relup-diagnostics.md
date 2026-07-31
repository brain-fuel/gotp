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
parity remains required before either declaration can be conformant.

## Traceability

- Decision: `adr:0051-typed-systools-relup-diagnostics`.
- Pinned source: `OTP-29.0.4:lib/sasl/src/systools_relup.erl#format_error/1`.
- Code: `gotp.otp.systools-relup-diagnostics`.
- Laws: `test:gotp.otp.systools-relup-diagnostic-laws`.
- Differential law: `test:gotp.otp.systools-relup-otp29-differential`.
- Oracle: official `erlang:29.0.4-alpine` image at manifest digest
  `sha256:a6e2d0c34adb0038f98953d89d82a501a26b8905027a8e840bf8851531de75d8`.
- Corpus: `otp/release/testdata/otp-29.0.4-systools-relup.corpus` at
  `sha256:5afc27ca1ad58bd470440a64b28234e74f20f117c7371da4eaeb3c3dd646082e`.
