# Native tuple-key lookup

## Contract

The OTP runtime registry supplies `lists:keyfind/3`, `lists:keymember/3`, and
`lists:keysearch/3` as native export overrides.

The position is a positive one-based integer. The input is a proper list. Each
tuple with sufficient arity is inspected in list order; other elements are
skipped. Keys compare using Erlang `==`, so integer `1` compares equal to float
`1.0`. The first matching tuple wins.

Invalid positions, improper lists, invalid terms, and unordered floating values
reject with `badarg`.

## Results

- `keyfind` returns the matching tuple or `false`.
- `keymember` returns `true` or `false`.
- `keysearch` returns `{value, Tuple}` or `false`.

## Evidence

Pinned OTP 29 `lists.beam` invocation laws cover all three native exports,
including loose numeric comparison, missing-key behavior, result shape, and
invalid-position rejection.

## Decision

See ADR `0017-native-tuple-key-bifs`.
