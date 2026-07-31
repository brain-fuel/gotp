# Connected distribution controls are closed validated values

- ADR: `adr:gotp.closed-distribution-controls`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable units: `code:gotp.distribution.control-messages`, `code:gotp.distribution.typed-connected`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Represent every documented, non-obsolete distribution control opcode through
36 as a sealed Go+ `ControlCode`. A `Control` can only be constructed from a
validated opcode-specific immutable field vector. Validation covers tuple
arity, PID/name/reference positions, MFA shape, proper spawn lists, spawn flag
bits, and the full positive 64-bit unlink identifier range.

Classify payload presence as a closed required/forbidden rule and validate
spawn argument payloads as proper lists. Layer typed control decoding over the
existing transactional header and versionless ETF codec.

## Consequences

Kernel integration cannot receive an unknown or structurally malformed control
tuple. Obsolete `UNLINK` and unassigned opcodes are rejected. Semantic handling
of each operation, negotiated feature transitions, outbound atom selection,
fragmentation, and network transport remain incomplete.

## Evidence

`test:gotp.distribution.control-message-laws` round-trips every supported opcode,
checks payload rules and typed framing, rejects malformed and obsolete forms,
and property-tests arbitrary opcode/arity tuples for totality.
