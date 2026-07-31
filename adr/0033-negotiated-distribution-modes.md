# Distribution feature modes transition monotonically per direction

- ADR: `adr:gotp.negotiated-distribution-modes`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable unit: `code:gotp.distribution.negotiated-controls`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Validate feature-dependent controls against the flags intersected during the
handshake. Track SEND/SEND_SENDER and embedded-exit/payload-exit modes as
connection-local closed states. The first modern control advances its mode;
legacy controls in that direction are rejected afterward.

Serialize validation and transition under one lock and publish state only after
all flag and downgrade checks pass. Require explicit flags for sender-bearing,
payload-exit, alias, spawn, and unlink-ID operations.

## Consequences

Concurrent receives have one deterministic transition order and rejected input
cannot mutate policy state. This prevents protocol downgrade after modern mode
has become observable. Mandatory baseline-flag validation, outbound policy,
kernel dispatch, fragmentation, and transport remain incomplete.

## Evidence

`test:gotp.distribution.negotiated-control-laws` covers unadvertised features,
sender and exit downgrades, all embedded exit families, and concurrent first
transition serialization.
