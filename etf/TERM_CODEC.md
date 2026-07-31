# Canonical immutable-term ETF codec

`CanonicalCodec` bridges GoTP's immutable `term.Term` model to the Erlang
External Term Format. It emits modern UTF-8 atoms, `NEW_PID_EXT`,
`NEWER_REFERENCE_EXT`, and `V4_PORT_EXT`; it also decodes their legacy forms.
Maps are sorted by encoded key bytes so equal GoTP maps have deterministic
binary output.

Encoding and decoding return `result.Result` with the closed ETF `Failure`
algebra. Identifier encoding requires a `NodeResolver`; its lookups return
`option.Option`. This is an explicit wire capability that maps compact local
node IDs to node-name atoms without putting distributed naming policy into the
kernel.

The separate raw decoder returns a sealed `RawTerm` enum, preserving ETF
shapes that do not yet belong to the immutable runtime term model.

The decoder bounds total input, decompression, nesting, containers, binaries,
and bignums. Distribution atom-cache references, bitstrings, funs, exports, and
local-only terms remain separate compatibility items.
