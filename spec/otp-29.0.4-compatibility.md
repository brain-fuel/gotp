# OTP 29.0.4 compatibility specification

- Artifact: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.compatibility-evidence`
- Declaration decision: `adr:gotp.pinned-otp-public-declarations`
- Header decision: `adr:gotp.pinned-otp-public-headers`
- Java decision: `adr:gotp.pinned-jinterface-binary-api`
- Native-entry decision: `adr:gotp.pinned-native-loadable-entries`
- Native ABI decision: `adr:gotp.pinned-darwin-arm64-native-abi`
- Native macro decision: `adr:gotp.pinned-native-api-macros`
- Hot-code decision: `adr:gotp.two-version-hot-code-state`
- Deployable unit: `code:gotp.compat.ledger`
- Upstream tag: `OTP-29.0.4`
- Upstream commit: `1259612946cb36a8bf9614b289090bb32fbcbeb2`

## Required outcome

GoTP reaches semantic feature compatibility when the complete upstream
inventory is represented, every applicable capability is conformant under its
declared assurance level, and interoperability suites accept artifacts from
Erlang, Elixir, Gleam, LFE, and other BEAM producers without source changes.
API parity with Erlang/OTP is not required.

## Ledger rules

1. IDs are stable semantic identities and never contain source line numbers.
2. `conformant` entries include executable differential or property evidence.
3. `partial` and `missing` entries prevent a parity claim.
4. `unavailable` entries explain why an upstream capability is inapplicable.
5. `inventory_complete` is set only after the pinned upstream inventory is independently audited.
6. Canonical serialization sorts capabilities and evidence deterministically.

## Assurance

Each entry uses the GoTP proof vocabulary: `Foreign`, `BoundaryChecked`,
`ResourceSafe`, `Total`, or `ClosedVerified`. Assurance states what has been
established; it does not elevate compatibility status by itself.

## Current state

`compat/otp-29.0.4-inventory.json` deterministically inventories 36 shipped OTP
applications, 1,268 Erlang modules, and 981 production source units from the
pinned Git tree. The source partition is 860 native C/assembly units, 57 Java
units, 14 generator specifications, and 50 public headers. A content-pinned
declaration manifest additionally inventories 38,448 exported functions, 1,655
exported types, 335 required callbacks, and 125 optional callbacks. The 50
public Erlang headers contribute 10,973 object macros, 110 function macros, 636
records, and 61 types. Every unit has an explicit row in
`compat/otp-29.0.4.json`. JInterface contributes 730 descriptor-exact public
and protected JVM symbols. Production native sources contribute 15 NIF modules,
279 Erlang-callable NIF functions, and 2 drivers. Four compiler-profiled native
macro manifests add 1,047 NIF, driver, and EI obligations: 186 on each POSIX
profile and 489 on Windows. The current ledger contains 60,251 rows, including
60,236 missing units and 15 coarse partial capabilities.

The ledger deliberately keeps `inventory_complete` false. Declaration
semantics, protocols, tools, generated outputs, native and Java public symbols,
and behavioral requirements still require independent inventories. Declaration
coverage is therefore evidence of honest scope expansion, not feature parity.

Regenerate the source manifest from a previously fetched GitHub recursive-tree
payload with:

```sh
go run ./cmd/otpinventory /path/to/otp-tree.json > compat/otp-29.0.4-inventory.json
```

Regenerate declarations from a pinned OTP checkout with:

```sh
go run ./cmd/otpdeclarations /path/to/otp-OTP-29.0.4 compat/otp-29.0.4-inventory.json > compat/otp-29.0.4-declarations.json
```

Regenerate public header declarations with:

```sh
go run ./cmd/otpheaders /path/to/otp-OTP-29.0.4 compat/otp-29.0.4-inventory.json > compat/otp-29.0.4-headers.json
```

Regenerate the JInterface binary API with the pinned compiler:

```sh
go run ./cmd/otpjavaapi /path/to/javac /path/to/otp-OTP-29.0.4 compat/otp-29.0.4-inventory.json /tmp/otpjavaapi > compat/otp-29.0.4-java-api.json
```

Regenerate native loadable entry points with:

```sh
go run ./cmd/otpnativeentries /path/to/otp-OTP-29.0.4 compat/otp-29.0.4-inventory.json > compat/otp-29.0.4-native-entries.json
```

Regenerate each native ABI profile with its pinned compiler:

```sh
go run ./cmd/otpnativeabi /usr/bin/clang /path/to/otp-OTP-29.0.4 /tmp/otpnativeabi darwin-arm64-lp64 > compat/otp-29.0.4-native-abi-darwin-arm64.json
go run ./cmd/otpnativeabi /path/to/zig /path/to/otp-OTP-29.0.4 /tmp/otpnativeabi linux-amd64-lp64 > compat/otp-29.0.4-native-abi-linux-amd64.json
go run ./cmd/otpnativeabi /path/to/zig /path/to/otp-OTP-29.0.4 /tmp/otpnativeabi linux-arm64-lp64 > compat/otp-29.0.4-native-abi-linux-arm64.json
go run ./cmd/otpnativeabi /path/to/zig /path/to/otp-OTP-29.0.4 /tmp/otpnativeabi windows-amd64-llp64 > compat/otp-29.0.4-native-abi-windows-amd64.json
```

Generate an active macro dump with each pinned profile compiler, then normalize
only macros declared by the canonical OTP headers:

```sh
go run ./cmd/otpnativemacros darwin-arm64-lp64 /path/to/otp-OTP-29.0.4 /tmp/native-macros-darwin-arm64.txt > compat/otp-29.0.4-native-macros-darwin-arm64.json
go run ./cmd/otpnativemacros linux-amd64-lp64 /path/to/otp-OTP-29.0.4 /tmp/native-macros-linux-amd64.txt > compat/otp-29.0.4-native-macros-linux-amd64.json
go run ./cmd/otpnativemacros linux-arm64-lp64 /path/to/otp-OTP-29.0.4 /tmp/native-macros-linux-arm64.txt > compat/otp-29.0.4-native-macros-linux-arm64.json
go run ./cmd/otpnativemacros windows-amd64-llp64 /path/to/otp-OTP-29.0.4 /tmp/native-macros-windows-amd64.txt > compat/otp-29.0.4-native-macros-windows-amd64.json
```
