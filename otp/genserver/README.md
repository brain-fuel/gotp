# Typed `gen_server`

This package is GoTP's typed primary API for the first OTP behavior. Application
code supplies codecs and typed call/cast handlers. The package owns the
`$gen_call`, `$gen_cast`, and `$gen_reply` term envelopes so compatibility
protocol details do not leak into normal Go+ code.

Implemented bootstrap semantics:

- monitored calls and selective reply matching;
- asynchronous casts;
- one event per scheduler reduction;
- typed state transitions through `ContinueCall`, `StopCall`,
  `ContinueEvent`, and `StopEvent`;
- client polling through `Pending`, `ReplyReceived`, and `ServerDown` rather
  than a `(value, ready, error)` tuple;
- callback failures become process exit reasons;
- unknown messages and system signals flow through `HandleInfo`.

Codecs, callbacks, construction, casts, and calls use the package's closed
`Failure` algebra through `result.Result`.

Timeouts, continuations, names, distributed aliases, `sys`, hibernation, and
code-change callbacks remain compatibility-ledger items, not claimed parity.
