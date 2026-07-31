# GoTP

GoTP is a Go+-first, Go-hosted implementation of the BEAM runtime and OTP
platform. It targets behavioral compatibility with Erlang/OTP without making
OTP's dynamic API the primary Go+ programming model.

The current implementation is an executable reference-runtime foundation:

- safe IFF/BEAM chunk loading and structural verification;
- an OTP-29.0.4 opcode inventory and bounded compact-operand decoder;
- a bootstrap reference interpreter for local calls, tail calls, register
  moves, stack allocation, jumps, and returns;
- atom, import, export, and code-header inspection;
- bounded raw and canonical immutable-term ETF codecs;
- proof and foreign-assumption manifests;
- generation-checked off-heap process storage from `goplus/std/memory`;
- a deterministic actor kernel with selective receive, links, monitors,
  trap-exit behavior, and per-route signal ordering;
- typed `gen_server` and static supervisor foundations;
- `gotp inspect`, `gotp verify`, and `gotp etf` commands.

This is not OTP parity. Most BEAM instructions, distribution, ports,
NIF/driver ABI, JIT targets, complete OTP applications, the Go compatibility
domain, and WASM profiles remain open inventory rows.

Go+ owns the source semantics. Runtime APIs use closed enums, exhaustive
matches, `Result`, `Option`, and explicit capabilities. Checked-in generated Go
is an interoperability and tooling artifact, not an alternative source of
truth.

## Build

```sh
go generate ./...
go test ./...
go run ./cmd/gotp inspect path/to/module.beam
go run ./cmd/gotp verify path/to/module.beam
go run ./cmd/gotp etf path/to/term.etf
```

The checked-in `go.work` links the adjacent Go+ toolchain and standard library
during development without adding publish-blocking `replace` directives.

## Tests

Tests are authored in `_test.gp` and generated to `_gp_test.go`. The generated
files run under the normal Go toolchain, so GoTP retains `testing`,
`testing/quick`, fuzzing, coverage, `go test -race`, and `go vet` without
duplicating that ecosystem.

```sh
go generate ./...
go tool goplus gen -check ./...
go test ./...
go test -race ./...
go vet ./...
```

Property laws are preferred over isolated examples. Go standard-library errors
are folded into typed Go+ results at the foreign boundary.

## Licensing

The GoTP core is MIT. Erlang/OTP is Apache-2.0. Any copied upstream header,
fixture, generated table, or temporarily bundled application must be recorded
under `third_party/` with its original license and pinned source identity.
