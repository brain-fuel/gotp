# ADR 0019: ETF function forms are explicit immutable identities

## Status

Accepted.

## Context

Erlang distribution uses three function encodings with materially different
identity: historical `FUN_EXT`, modern `NEW_FUN_EXT`, and external
`EXPORT_EXT`. A flat local-closure record cannot preserve the modern 128-bit
digest, both modern indexes, creator PID, or exported MFA distinction.

## Decision

`Fun` carries a sealed `FunForm`: `LocalClosure`, `OldClosure`, `NewClosure`, or
`ExportedFunction`. New closures retain the 16-byte digest, new index, and old
index. Old and new closures retain creator PID, old unique value, and immutable
free variables. Exported functions retain module, function, and visible arity.

The canonical ETF codec implements tags 117, 112, and 113 using its existing
node resolver, nested-term recursion, and limits. `NEW_FUN_EXT.Size` is checked
as the total bytes including its four-byte Size field. Free-variable count is
bounded by `MaxContainer`; malformed field types, ranges, creator PIDs, sizes,
or trailing payload bytes return typed failures.

VM-created local closures remain intentionally non-encodable until ERTS assigns
creator PID and code-version identity. No synthetic identity is invented.

## Reference

Erlang/OTP External Term Format, sections `FUN_EXT`, `NEW_FUN_EXT`, and
`EXPORT_EXT`: <https://www.erlang.org/doc/apps/erts/erl_ext_dist.html>.

## Traceability

- Specification: `spec/etf-functions.md`
- Source units: `gotp.term.fun`, `gotp.etf.fun-codec`
- Laws: `gotp.term.fun-laws`, `gotp.etf.fun-codec-laws`
