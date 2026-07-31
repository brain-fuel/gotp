# ADR 0010: Load immutable modules into process-isolated machines

## Status

Accepted

## Context

A parsed BEAM module contains immutable code and metadata, while a VM machine contains mutable process-local registers, stacks, program counters, and accounting. Reusing a machine across process spawns would violate BEAM isolation and make scheduler behavior non-deterministic.

## Decision

`LoadedModule` retains decoded instructions, validated atom names, bounded immutable literal terms, and export labels. Its fields are private and its only machine factory invokes `vm.NewMachine`, which clones mutable configuration pools and allocates fresh execution state. Export lookup uses a structural `{function, arity}` key and a closed `ModuleLoadFailure` sum.

Filesystem loading requires `beam.ReadFileCapability`; byte loading stays pure. Decode limits flow unchanged into the BEAM decoder. Real OTP unsigned compact label operands are refined alongside explicit label operands at the VM boundary.

## Consequences

One decoded instruction slice can be shared read-only while every process owns its mutable machine. Malformed modules, invalid atoms, duplicate exports, missing labels, VM construction failures, and adapter failures remain exhaustively distinguishable.

Cross-module continuation linking, NIF loading, and complete opcode execution remain explicit missing work and prevent a conformant code-loading claim.

## Traceability

- Specification: `spec/beam-module-loading.md`
- Code artifact: `gotp.erts.module-loader`
- Law artifact: `gotp.erts.module-loader-laws`
- Literal law artifact: `gotp.beam.literal-table-laws`
- Upstream fixture: `beam/testdata/otp-29.0.4/lists.beam`
