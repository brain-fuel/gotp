# ADR 0025: Runtime tracing is an explicit bounded capability

## Status

Accepted.

## Context

Unbounded global trace callbacks can retain arbitrary process terms, perturb
scheduler behavior, and permit observers to mutate shared backing data.

## Decision

The kernel accepts an explicit tracer with a positive record capacity. Runtime
transitions emit a sealed Go+ event enum. The tracer clones term payloads,
assigns deterministic monotonic sequence numbers, and evicts oldest records at
capacity. Snapshot returns a second clone boundary.

## Traceability

- Parent specification: `spec/runtime-tracing.md`
- Compatibility item: `system.tracing`
- Source unit: `gotp.kernel.runtime-tracing`
- Laws: `gotp.kernel.runtime-tracing-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, ERTS tracing
