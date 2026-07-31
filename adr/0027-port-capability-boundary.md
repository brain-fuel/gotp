# ADR 0027: Ports require explicit driver sessions

## Status

Accepted.

## Context

Ambient subprocess or native-driver access would bypass effect tracking and let
untrusted BEAM code acquire host resources without a capability boundary.

## Decision

Port opening requires an explicit driver function that returns a complete
session. The synchronized manager owns BEAM port identity and ownership rules;
each session serializes commands and close. Binary data is cloned in both
directions, and owner exit closes all connected ports.

## Traceability

- Parent specification: `spec/ports.md`
- Compatibility item: `system.ports-nifs`
- Source unit: `gotp.erts.port-manager`
- Laws: `gotp.erts.port-manager-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, ports and port drivers
