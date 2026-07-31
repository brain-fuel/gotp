# Structured exception propagation

## Native boundary

An external implementation can return a value, report itself unbound, reject a
call as an invalid host operation, or raise with term-valued class and reason.
Raised terms are cloned before entering VM state.

`erlang:error/1`, `/2`, and `/3` raise class atom `error` and preserve their
first argument exactly as reason.

`erlang:throw/1` and `erlang:exit/1` preserve their argument with class `throw`
and `exit`. `erlang:raise/3` accepts the three exception-class atoms and
preserves its reason; supplied stacktrace installation remains incomplete.

## VM boundary

`RaisedException` is distinct from invalid configuration, malformed bytecode,
missing constants, resource limits, and unsupported opcodes. Executing
`func_info` raises `error:function_clause`.

`ExecutionRaised` carries class, reason, reductions consumed in the current
slice, instructions consumed in the current slice, and total machine
instructions. It is a successful continuation observation, not a host/compiler
failure rail.

## Handler boundary

`catch` and `try` create typed restoration frames containing an opaque Y-register
token, module image, handler label, return depth, and Y-stack depth. Raising
restores that state and supplies class, reason, and trace in X0, X1, and X2.
The selected frame is inactive during handler execution, so a second exception
unwinds to the next enclosing frame.

`try_end` and `try_case` remove try frames. `catch_end` removes old catch frames
and returns a thrown reason directly, an exit as `{EXIT, Reason}`, and an error
as `{EXIT, {Reason, Stack}}`. Trace construction currently yields an empty list.

The failure opcodes produce OTP-shaped reasons: `{case_clause, Value}` for
`case_end`, `{badmatch, Value}` for `badmatch`, `if_clause` for `if_end`,
`{badrecord, Value}` for `badrecord`, and `{try_clause, Value}` for
`try_case_end`.

## ERTS boundary

The adapter accumulates raised progress and transitions to `VMProcessRaised`.
Term-valued class and reason remain inspectable. Subsequent scheduler steps stop
with `{gotp_exception, Class, Reason}`.

## Evidence

A synthetic VM law proves term preservation and exact progress through an
external tail call. A `func_info` law proves `function_clause`. Pinned OTP 29
`lists.beam` laws prove `lists:seq(1,3,0)` raises `error:badarg` through
`erlang:error/*` and `lists:nth(0,[a])` raises `error:function_clause`, both with
nonzero reduction and instruction accounting.

Handler laws prove try class/reason transfer, old-catch translation for all
three classes, and nested unwinding past an inactive inner handler.

## Decision

See ADR `0020-structured-exception-propagation`.
Handler restoration is decided by ADR `0021-beam-exception-handlers`.
