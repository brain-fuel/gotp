# Pinned gen_statem observability and formatting

- Specification: `spec:gotp.otp.gen-statem-observability-formatting`
- Parent: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.pinned-gen-statem-observability-formatting`
- Deployable code: `code:gotp.erts.otp29-gen-statem-format`

GoTP executes the unmodified OTP 29.0.4 `gen_statem.beam` diagnostic surface.
Differential corpora cover `format_log/1,2`, `format_status/2`, modern
`format_status/1`, and deprecated `format_status/2` callbacks in both
`state_functions` and `handle_event_function` modes.
Fixture and corpus provenance is pinned in
`erts/testdata/otp-29.0.4/GEN_STATEM_FORMAT_CALLBACK_PROVENANCE.md`.

Evidence includes termination and crash diagnostics, queued and postponed
events, state and data, active time-outs, Unicode output, multi-line and
single-line output, depth and character limits, normal and suspended
`sys:get_status`, callback redaction, malformed public arguments, and malformed
callback returns. A generated law varies state, data, event, and formatting
options and requires deterministic output and callback-mode equivalence.

These declarations remain partial because exhaustive logger report, option,
system-state, callback-return, and malformed-term domains remain open. The
exported `format_status/0` type is not promoted by runtime behavior evidence.

The complete post-slice inventory audit fixes the evidence boundary at 39
partial executable functions, 8 partial required callbacks, 6 partial optional
callbacks, and 25 missing exported types. Every partial row must retain at
least one behavioral artifact; every type row requires separate static type
compatibility evidence before promotion.
