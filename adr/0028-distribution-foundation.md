# Distribution semantic foundation before transport interoperability

- ADR: `adr:gotp.distribution-foundation`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable units: `code:gotp.distribution.handshake`, `code:gotp.distribution.ordered-channel`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Implement authentication and ordered message semantics independently of any
socket implementation. Inject challenge generation as a capability, represent
handshake phases with distinct Go+ types, use the OTP cookie/challenge digest,
and encode immutable envelopes through the existing canonical ETF capability.

This separation makes authentication deterministic under test, prevents
out-of-order API use, avoids ambient node registries, and permits TCP, TLS, or
test transports to share one semantic core.

## Consequences

The package establishes laws needed by future wire adapters but cannot connect
to an Erlang node. The compatibility item is therefore partial. A wire adapter
must implement and differentially test every packet and control-message format
before interoperability can be claimed.

## Evidence

`test:gotp.distribution.handshake-laws` verifies mutual authentication,
independent cookie directions, deterministic challenge injection, digest
tamper rejection, and flag negotiation.
`test:gotp.distribution.ordered-channel-laws` verifies canonical output,
ownership isolation, exact ordering, replay rejection, and transactional
handling of corrupt frames.
