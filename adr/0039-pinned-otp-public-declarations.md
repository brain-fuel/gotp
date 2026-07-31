# Public Erlang declarations are individually traceable compatibility requirements

- ADR: `adr:gotp.pinned-otp-public-declarations`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-public-declarations`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Extract every literal `-export`, `-export_type`, `-callback`, and
`-optional_callbacks` declaration from the 1,268 modules in the pinned source
manifest. Represent function or type name and arity as a stable semantic ID;
encode the original Erlang name rather than source location so moves and
formatting changes do not break traceability.

The deterministic input identity is SHA-256 over each module's sorted relative
path and exact source bytes. Parsing is lexical: comments and string contents
cannot produce declarations, while quoted atoms and operator names remain
significant. Unsupported declaration syntax fails generation rather than being
silently omitted.

## Consequences

The compatibility ledger gains 40,563 explicit missing requirements: 38,448
exported functions, 1,655 exported types, 335 required callbacks, and 125
optional callbacks. Module-level entries can no longer conceal absent public
surface. These rows inventory declarations but do not yet inventory declaration
semantics, protocols, generated outputs, tools, or runtime behavior, so global
`inventory_complete` remains false.

## Evidence

`test:gotp.compat.otp-public-declaration-laws` proves the pinned source digest,
exact kind partition, strict ordering, complete ledger coverage, lexical
string/comment exclusion, quoted and tuple syntax, stale-input rejection, and
malformed-input totality.
