# Pinned collection callback fixtures

`ordsets_callbacks.beam` and `queue_callbacks.beam` are compiled from their
adjacent Erlang sources with the compiler in the official
`erlang:29.0.4-alpine` image. They exist only to pass ordinary BEAM closures to
the corresponding unmodified OTP stdlib modules.

- `ordsets_callbacks.beam`: `4178105c18f1e54569cb9f40b2b263258f79221a0b78a8aee6d727074df3b138`
- `queue_callbacks.beam`: `d5eb79557d066da8f2d1fc85e479ae5f093cf85157e27347fd736b2ba151498a`
- `gb_sets_callbacks.beam`: `d06fbae0afdb64c0b37f1542af4f1e7bd8eefb34e141dfe58294de12b32d7513`
- `gb_trees_callbacks.beam`: `a7f23a9845f524a2b4a51b1e1495ad147b3fb64b241256db5f4a9653f3969a03`
