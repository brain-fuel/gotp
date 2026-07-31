# ETF function terms

## Forms

`FUN_EXT` encodes an old closure with free-value count, creator PID, module,
integer index, integer unique value, and free terms.

`NEW_FUN_EXT` encodes total Size, one-byte visible arity, 16-byte digest,
new index, free-value count, module, old index, old unique value, creator PID,
and free terms. Size includes the four-byte Size field but excludes the tag.

`EXPORT_EXT` encodes module atom, function atom, and small-integer arity.

## Validation

- Creator PIDs must resolve through the explicit node capability.
- Integer identity fields must fit unsigned 32-bit values.
- Export and modern-fun arities must fit one byte.
- Free-value count must not exceed `TermLimits.MaxContainer`.
- Every nested free value consumes one depth level and the normal byte limits.
- `NEW_FUN_EXT` decoding must end exactly at its declared boundary.
- VM-local closures without creator/code identity reject encoding.

## Identity

Exact equality includes form, digest/index data, module/function/arity, creator,
old unique value, and free variables. Total term ordering compares the same
identity fields before environments.

## Evidence

Laws round-trip old, modern, and exported funs; shrink arbitrary modern-fun
environments; verify `NEW_FUN_EXT` Size; reject malformed Size and identity-less
local closures; and check an independently authored official `EXPORT_EXT` byte
layout.

## Decision

See ADR `0019-etf-function-identities`.
