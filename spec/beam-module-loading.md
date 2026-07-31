# BEAM module loading

GoTP loads OTP-29.0.4 BEAM containers into process-isolated VM machines through a pure decoder or an explicit filesystem capability.

## Contract

- The existing BEAM parser validates IFF framing, required chunks, atom/import/export tables, instruction-set format, opcode bounds, compact operands, and decode resource limits.
- A loaded module owns immutable decoded instructions, a validated one-based atom pool, and a unique `{function, arity}` export index.
- Every process receives a fresh mutable `vm.Machine`; machines never share registers, stacks, return addresses, or instruction counters.
- Export labels must exist in decoded code before the module is accepted.
- `LitT` entries decode from OTP-28/29 uncompressed or legacy zlib payloads into bounded immutable runtime terms with zero-based indexes.
- Real OTP compact label operands and explicit semantic label operands refine to the same VM label type.
- `LoadModuleFile` requires `beam.ReadFileCapability`; pure callers use `DecodeModule`.

## Current boundary

- Import calls bind to explicit synchronous native/BIF registries; cross-module BEAM continuation transfer and NIF loading remain unavailable.
- Loading proves structural validity and process isolation, not executable support for every decoded opcode.

These boundaries keep `beam.code-loading` partial until cross-module linking and full instruction execution are proven.

## Executable evidence

- `gotp.erts.module-loader`
- `gotp.erts.module-loader-laws`
- `gotp.beam.literal-table-laws`
- `gotp.erts.call-registry-laws`
- Pinned fixture: `beam/testdata/otp-29.0.4/lists.beam`
