# Execute pinned gen_statem diagnostics through both callback modes

- ADR: `adr:gotp.pinned-gen-statem-observability-formatting`
- Parent specification: `spec:gotp.otp.gen-statem-observability-formatting`
- Deployable unit: `code:gotp.erts.otp29-gen-statem-format`
- Reference implementation: OTP `OTP-29.0.4` `lib/stdlib/src/gen_statem.erl`

## Decision

Execute the official unmodified `gen_statem.beam` formatter rather than
reimplementing logger and system-status rendering in Go. Compile source-visible
fixtures with the pinned official compiler and encode oracle results as
deterministic ETF.

Exercise modern and legacy status callbacks independently in both callback
modes. Normalize only process identifiers, references, and process-dictionary
ordering. Preserve all state-machine diagnostics, callback fallback text, and
rendered bytes exactly. Require generated state/data/event reports to be stable
across repeated execution and equal across callback modes.

## Evidence

`test:gotp.erts.otp29-gen-statem-format` consumes both official corpora.
`test:gotp.erts.gen-statem-format-determinism` proves generated determinism and
mode equivalence. `test:gotp.erts.gen-statem-complete-inventory-audit` combines
this evidence with core lifecycle, asynchronous request, and export-ledger
coverage while preventing runtime evidence from promoting exported types.
