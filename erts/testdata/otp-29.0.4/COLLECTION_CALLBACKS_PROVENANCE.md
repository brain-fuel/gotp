# Pinned collection callback fixtures

`ordsets_callbacks.beam` and `queue_callbacks.beam` are compiled from their
adjacent Erlang sources with the compiler in the official
`erlang:29.0.4-alpine` image. They exist only to pass ordinary BEAM closures to
the corresponding unmodified OTP stdlib modules.

- `ordsets_callbacks.beam`: `4178105c18f1e54569cb9f40b2b263258f79221a0b78a8aee6d727074df3b138`
- `queue_callbacks.beam`: `d5eb79557d066da8f2d1fc85e479ae5f093cf85157e27347fd736b2ba151498a`
