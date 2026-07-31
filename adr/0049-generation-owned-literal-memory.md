# ADR 0049: Generation-owned literal memory

## Status

Accepted, incomplete ERTS memory slice.

## Specification

GoTP module generations need bounded literal storage that does not make every
encoded literal an independently collected heap object. Go+ std artifact
`goplus.std.memory-group` owns related arena handles, and artifact
`goplus.std.memory-soa` stores literal identities and handles column-wise.
GoTP artifact `gotp.erts.literal-arena` composes both abstractions.

Reset securely erases and reclaims every encoded literal, invalidates all prior
handles, retains reusable arena and column capacity, and starts an empty logical
generation. Release permanently closes the group and arena. Reads return copies
rather than mutable arena aliases.

## Traceability

- Decision: `adr:0049-generation-owned-literal-memory`.
- Std code: `goplus.std.memory-group`, `goplus.std.memory-soa`.
- Std laws: `test:goplus.std.memory-group-laws`,
  `test:goplus.std.memory-soa-laws`.
- Consumer code: `gotp.erts.literal-arena`.
- Consumer laws: `test:gotp.erts.literal-arena-laws`.

## Remaining obligations

The BEAM loader now transfers each module's encoded `LitT` chunk into this
ownership boundary. Successful hot-code installation transfers ownership to the
runtime generation; busy soft purge retains it, while successful soft purge and
forced purge close it and report the reclaimed literal count. Decoded
`term.Term` representation, current-generation removal, process heaps, message
fragments, binaries, stacks, and scheduler-local caches remain separate memory
parity obligations. This ADR does not establish ERTS memory parity.
