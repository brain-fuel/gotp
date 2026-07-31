# ADR 0020: Exceptions preserve class, reason, and execution progress

## Status

Accepted.

## Context

Native calls previously returned only values, unbound status, or string
rejections. VM failures collapsed into `VMProcessFailed`, losing Erlang
exception class and reason. In addition, `func_info` was treated as a no-op;
when clause dispatch fell through to it, execution looped instead of raising
`function_clause`.

## Decision

Native effects can return `ExternalCallRaised(Class, Reason)`. External calls
and BIF instructions convert that outcome to `RaisedException` without string
formatting. `func_info`, when executed, raises `error:function_clause`.

The continuation converts raised failures into `ExecutionRaised`, carrying the
same reduction and instruction progress fields as completed or suspended work.
The ERTS adapter accumulates that progress and exposes
`VMProcessRaised(Class, Reason, TotalReductions, TotalInstructions)`. Kernel stop
reason is the explicit tuple `{gotp_exception, Class, Reason}` until full OTP
exit-reason/stack semantics are available.

The default OTP registry binds `erlang:error/1`, `/2`, and `/3`; each preserves
the first argument as reason and raises class `error`. Additional arguments will
feed stacktrace metadata in the later stacktrace slice.

External/start transfer steps past an immediately adjacent `func_info` to keep
legacy synthetic module fixtures valid. Internal fall-through and jumps still
execute it and raise.

## Incomplete boundary

Catch/try frames, `throw`, `exit`, stacktrace frame construction, exception
options, and OTP-compatible process exit reasons remain required for parity.

## Traceability

- Specification: `spec/exceptions.md`
- Source units: `gotp.vm.exception-propagation`,
  `gotp.erts.otp-exception-bifs`, `gotp.erts.vm-process-exceptions`
- Laws: `gotp.vm.exception-propagation-laws`,
  `gotp.erts.pinned-otp-exception-laws`
