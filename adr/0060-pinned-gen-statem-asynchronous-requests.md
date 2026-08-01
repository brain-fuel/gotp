# Reuse monitor-alias request lifecycles for gen_statem

- ADR: `adr:gotp.pinned-gen-statem-async-requests`
- Parent specification: `spec:gotp.otp.gen-statem-async-requests`
- Deployable unit: `code:gotp.erts.otp29-gen-statem-async`
- Reference implementation: OTP `OTP-29.0.4` `lib/stdlib/src/gen_statem.erl`

## Decision

Execute the asynchronous exports from the official `gen_statem.beam` rather
than adding a host-side request API. Use one source-visible semantic fixture
with thin `state_functions` and `handle_event_function` adapters. Generate an
isolated deterministic ETF corpus for each mode and require byte-identical
semantic outcomes.

Use the existing monitor-alias, receive-marker, selective-mailbox, and process
exit implementation without a `gen_statem` special case. Prove deletion with
stateful release permutations and prove retention separately because a retained
request identifier cannot be awaited again after its response is consumed.

## Evidence

`test:gotp.erts.otp29-gen-statem-async-requests` covers all fourteen exports
through 17 scenarios per callback mode.
`test:gotp.erts.gen-statem-request-collection-order` checks generated release
orders and collection cardinalities in both callback modes.

Both ledgers remain partial: complete invalid inputs and distributed server
references require separate evidence.
