# ADR 0021: BEAM exception handlers are typed restoration frames

## Status

Accepted.

## Context

ADR 0020 preserved uncaught exception class and reason across VM and scheduler
boundaries, but every exception still escaped the executing function. OTP 29
bytecode establishes lexical handlers with `catch` and `try`; an exception must
restore the handler's module, return stack, Y stack, and instruction pointer.

## Decision

The VM stores typed old-catch and try-catch frames. A frame owns an opaque token,
the active module image, handler label, return depth, Y-stack depth, and optional
pending exception. Unwinding selects the newest active frame, marks it inactive
before transferring control, restores saved execution state, and places class,
reason, and trace in X0, X1, and X2. An exception raised by handler code therefore
continues to the next enclosing active frame rather than catching itself.

`try_end` and `try_case` remove only try frames. `catch_end` removes only old
catch frames and applies OTP's result translation for throw, exit, and error.
The VM implements OTP 29's `raise`, `case_end`, `badmatch`, `if_end`, `badrecord`,
and `try_case_end` exception opcodes. The OTP registry provides `throw/1`,
`exit/1`, and `raise/3` alongside `error/1,2,3`.

## Incomplete boundary

X2 currently carries an empty trace and `raise/3` does not yet install its
supplied stacktrace. Full stack-frame construction, exception options, signal
exit semantics, and differential execution of pinned OTP catch/try modules
remain parity work.

## Traceability

- Parent specification: `spec/exceptions.md`
- Prior decision: `adr/0020-structured-exception-propagation.md`
- Source unit: `gotp.vm.exception-handlers`
- Native source unit: `gotp.erts.otp-exception-bifs`
- Laws: `gotp.vm.exception-handler-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, `erts/emulator/beam/emu/ops.tab`
