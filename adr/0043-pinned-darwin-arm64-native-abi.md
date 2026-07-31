# Native C ABI inventories form a target-profile matrix

- ADR: `adr:gotp.pinned-darwin-arm64-native-abi`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-native-abi`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Compile the canonical NIF, driver, and EI headers as Clang translation units and
normalize only declarations owned by OTP source locations. Inventory functions,
typedefs, records, fields, enums, enum constants, and variables with their
compiler-normalized signatures. System-header declarations are excluded.

Qualify every identity by target profile. Inventory `darwin-arm64-lp64` with
Apple Clang 21 and `linux-amd64-lp64`, `linux-arm64-lp64`, and
`windows-amd64-llp64` with Zig 0.16.0's bundled Clang and target libc headers.
Pin all eight contributing OTP headers by content digest.
Macro-expanded NIF API declarations are attributed through the known direct
include graph to account for Clang JSON location elision.

## Consequences

The ledger gains 3,535 ABI requirements: 866 Darwin ARM64, 855 Linux AMD64, 855
Linux ARM64, and 959 Windows AMD64 symbols. Windows dynamic callback tables are
represented as records and fields rather than ELF-style function declarations.
Function-like public C macros that do not materialize as declarations remain
explicit inventory work, so global `inventory_complete` stays false.

## Evidence

`test:gotp.compat.otp-native-abi-laws` proves exact surface and kind partitions,
known API presence across all profiles, system-symbol exclusion,
compiler/profile/source pins, strict ordering, complete ledger coverage,
macro-expansion ownership,
malformed-AST totality, and deterministic regeneration.
