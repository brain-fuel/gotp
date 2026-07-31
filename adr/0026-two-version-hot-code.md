# ADR 0026: Hot code is governed by generation leases

## Status

Accepted.

## Context

Replacing a module pointer in place cannot preserve OTP's current/old code
semantics and provides no evidence that executing processes stopped referencing
purged code.

## Decision

The code server owns a synchronized two-slot state per module. Generations have
stable identities and executing consumers hold explicit leases. Loading never
implicitly discards an old generation. Soft purge observes lease count; forced
purge invalidates resolution of outstanding old leases. Release is idempotent.

## Traceability

- Parent specification: `spec/hot-code.md`
- Compatibility item: `system.hot-code`
- Source unit: `gotp.erts.hot-code-server`
- Laws: `gotp.erts.hot-code-server-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, code server and purge semantics
