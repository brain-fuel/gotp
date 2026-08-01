# Model gen_statem wire types as sealed Go+ algebras

- ADR: `adr:gotp.pinned-gen-statem-static-types`
- Parent specification: `spec:gotp.otp.gen-statem-static-types`
- Deployable unit: `code:gotp.otp.genstatem-types`
- Reference implementation: OTP `OTP-29.0.4` `lib/stdlib/src/gen_statem.erl`

## Decision

Represent each exported OTP type with a public sealed Go+ type. Preserve OTP's
generic state and data parameters in callback result types. Keep reply tags,
request IDs, and request-ID collections opaque, exposing validated constructors
and defensive projections. Represent action cardinality canonically as slices,
while decoders accept OTP's single-action and action-list forms.

Use total term codecs with explicit path failures. Decode before entering the
VM, so malformed event types, context-invalid state-entry actions, callback
results, names, references, options, and status maps cannot enter typed APIs.
Treat OTP's overlapping `transition_option()` alias as its two wire-distinct
forms, boolean and timeout, rather than inventing role tags that cannot round
trip.

## Evidence

`test:gotp.otp.genstatem-type-codec-coverage` covers every type family.
`test:gotp.otp.genstatem-canonical-round-trip` supplies generated laws.
`test:gotp.otp.genstatem-illegal-results-do-not-compile` proves negative typing.
`test:gotp.erts.otp29-gen-statem-static-types` consumes the official acceptance
corpus, and `test:gotp.erts.gen-statem-types-integrate-runtime-slices` binds the
types to lifecycle, asynchronous request, and formatting behavior.
