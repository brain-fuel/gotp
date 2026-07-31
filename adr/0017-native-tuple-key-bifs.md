# ADR 0017: Native tuple-key lookup BIFs reuse term comparison

## Status

Accepted.

## Context

OTP 29 exports `lists:keyfind/3`, `keymember/3`, and `keysearch/3` as
runtime-native functions whose BEAM fallback bodies call `nif_error`. OTP defines
their key relation as “compares equal,” meaning Erlang `==`, not exact `=:=`.
A separate ad hoc equality routine would risk divergence from VM ordering,
especially for mixed integers and floats and exact map keys.

## Decision

The immutable OTP registry binds all three MFAs. Position must be a positive
one-based integer and the tuple collection must be a proper list. Non-tuples and
tuples shorter than the requested position are skipped. The first matching tuple
is cloned and returned.

Key comparison calls the checked term total order and matches `TermEqual`. This
gives loose numeric equality while retaining exact map-key ordering semantics.
`keyfind` returns the tuple or `false`; `keymember` returns a boolean atom;
`keysearch` returns `{value, Tuple}` or `false`.

## Traceability

- Specification: `spec/tuple-key-bifs.md`
- Source unit: `gotp.erts.otp-pure-bifs`
- Laws: `gotp.erts.otp-key-bif-laws`, `gotp.term.total-order-laws`
