# ADR 0001: Compatibility is an evidence-backed ledger

- Status: accepted
- Artifact: `adr:gotp.compatibility-evidence`
- Specifies: `spec:gotp.otp-29-0-4-compatibility`
- Implemented by: `code:gotp.compat.ledger`

## Context

OTP compatibility spans runtime semantics, protocols, system applications,
tooling, observability, and language-produced BEAM artifacts. A percentage or a
passing local test cannot identify what was measured, which upstream revision
was used, or which guarantees apply to each result.

## Decision

GoTP records compatibility in a deterministic, machine-readable ledger pinned
to an exact OTP tag and commit. Every capability has a stable semantic ID, a
status, an assurance level, and evidence. `conformant` requires evidence;
`unavailable` requires a reason. Overall completion is impossible until the
inventory itself is explicitly marked complete and no item remains `missing`
or `partial`.

Artifact references use stable logical identities such as
`artifact://code/gotp.compat.ledger`, not source line numbers. Assayxport owns
validation of the release-to-ADR-to-code closure.

## Consequences

Compatibility claims are auditable and deterministic. Adding code without a
linked reason is detectable. The initial ledger intentionally reports an
incomplete inventory and cannot be interpreted as OTP parity.
