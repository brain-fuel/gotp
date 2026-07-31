# Public Erlang header declarations are individual compatibility requirements

- ADR: `adr:gotp.pinned-otp-public-headers`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-public-headers`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Inventory records, object macros, function macros, types, and opaques from all
50 shipped application `.hrl` files. Pin exact source bytes through a canonical
path-and-content digest. Use header path, declaration kind, original Erlang
name, and arity as the stable identity; source line numbers are excluded.

Conditional definitions with the same semantic identity collapse into one
requirement. Lexical extraction excludes comments and string contents, retains
quoted atoms, and rejects malformed attributes instead of silently omitting
them.

## Consequences

The ledger gains 11,780 explicit requirements: 10,973 object macros, 110
function macros, 636 records, and 61 types. These describe source-level
compatibility consumed by Erlang, Elixir, Gleam, LFE, and other preprocessors;
they do not establish native ABI, Java API, protocol, or behavioral parity.

## Evidence

`test:gotp.compat.otp-public-header-laws` proves exact kind counts, source
digest, ordering, complete ledger coverage, conditional deduplication,
string/comment exclusion, stale-input rejection, and malformed-input totality.
