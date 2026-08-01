# Pinned gen_statem core lifecycle

- Specification: `spec:gotp.otp.gen-statem-core-lifecycle`
- Parent: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.pinned-gen-statem-core-lifecycle`
- Deployable code: `code:gotp.erts.otp29-gen-statem-core`

GoTP executes the byte-identical OTP 29.0.4 `gen_statem.beam`. Core lifecycle
evidence must cover both `state_functions` and `handle_event_function` callback
modes and compare equivalent operation traces. Construction, registration,
calls, casts, info events, state entry, transitions, internal events,
postponement, both repetition forms, timeout ordering, system state/code
operations, termination, callback exits, malformed callback returns, and the
change/push/pop callback-module action continuation paths are in this slice.
OTP 29.0.4 has no transition action named `continue`; continuation here means
processing the remaining action list after a callback-module action.

The export verifier derives its surface from the loaded BEAM export table and
requires every non-metadata export to have an inventory row. Request-ID APIs,
formatting, exported types, and full input-domain parity remain outside this
core-lifecycle slice. Their rows require separate evidence.
