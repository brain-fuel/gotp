# ADR 0057: Execute gen_server diagnostics through pinned OTP formatters

## Status

Accepted.

## Context

`gen_server:format_log/1,2` and `format_status/2` combine generic-server state,
callback-defined status, logger options, system-process metadata, Unicode
chardata, and OTP's term pretty printer. Host-language formatting cannot prove
byte compatibility.

## Decision

Execute the unmodified OTP 29.0.4 `gen_server`, `io_lib_format`, and
`io_lib_pretty` modules. Add only reusable VM semantics required by that path:
binary match contexts, strict boolean and bitwise BIFs, iodata and Unicode
conversion, tuple/list conversion, deterministic environment defaults, PID
text, and linked-module presence queries.

Compare rendered bytes and normalized live status against an isolated official
OTP corpus. Normalize only process dictionary enumeration and anonymous PID
headers, whose concrete identities or ordering are not part of formatted
server status. Add laws for deterministic formatting and equivalent formatted
status after ordinary startup and `enter_loop` startup.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by `gotp.erts.otp29-gen-server-format`,
`gotp.erts.gen-server-format-determinism`, and
`gotp.erts.gen-server-enter-loop-status-equivalence`.

## Consequences

Logger and status output is produced by OTP itself rather than duplicated in
Go. The seven proved declarations remain partial because exhaustive report,
option, callback-return, and malformed term domains remain open.
