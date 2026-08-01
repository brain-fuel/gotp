# Execute pinned gen_statem through mode-equivalent traces

- ADR: `adr:gotp.pinned-gen-statem-core-lifecycle`
- Parent specification: `spec:gotp.otp.gen-statem-core-lifecycle`
- Deployable unit: `code:gotp.erts.otp29-gen-statem-core`
- Reference implementation: OTP `OTP-29.0.4` `lib/stdlib/src/gen_statem.erl`

## Decision

Execute the official unmodified `gen_statem.beam`; do not reproduce its event
engine in host Go. Keep callback fixtures source-visible and compile them with
the pinned official toolchain. Represent oracle results as deterministic ETF.

Expose the same machine through both callback modes. Differential examples
establish exact lifecycle outcomes, while a stateful law applies generated
operation traces independently to both modes and requires equal final traces.
Runtime gaps discovered by these fixtures must be fixed as generic BEAM,
kernel, or BIF semantics rather than module-name special cases.

Treat callback-module continuation as the actual OTP action vocabulary:
`change_callback_module`, `push_callback_module`, and `pop_callback_module`.
The corpus processes a `next_event` after each module action, proving that the
remaining action list continues under the newly selected callback mode.

## Evidence

`test:gotp.erts.otp29-gen-statem-core-callback-modes` consumes the isolated
corpora. `test:gotp.erts.gen-statem-callback-mode-trace-equivalence` compares
generated traces. `test:gotp.erts.otp29-gen-statem-export-ledger-coverage`
binds the pinned BEAM digest and export table to the compatibility ledger.
`test:gotp.erts.gen-statem-timer-ordering` and
`test:gotp.erts.gen-statem-postponed-event-retry` bind ordering and retry
semantics independently of the differential examples.
