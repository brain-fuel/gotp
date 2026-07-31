# OTP stdlib BEAM parity

## Contract

GoTP executes the unmodified OTP 29.0.4 `lists` module through the ordinary
module loader, linker, continuation interpreter, external-call registry, and
kernel scheduler. The checked-in module must be byte-identical to the artifact
from the pinned official OTP image.

Every public BEAM export must have a deterministic oracle case. Exports that
accept callbacks must be exercised with closures compiled by the same pinned
OTP compiler. Outcomes compare returned ETF terms or raised class and reason.

`module_info` metadata is exact for module identity, attributes, compilation
information, and MD5. Export membership is exact. Export ordering is scoped to
the VM-wide export table because OTP derives it from previously created export
entries rather than from the loaded module's `ExpT` chunk.

The declaration ledger remains partial until laws cover each function's
declared input domain. Export coverage alone is not evidence of exhaustive
semantic parity.

## Pinned evidence

- OTP image: `erlang:29.0.4-alpine`
- `lists.beam` SHA-256: `06fad9cf6b27c05c020076b631795d8c06a48e2f05698a65cf1ef57725af3886`
- Non-callback corpus SHA-256: `209012d1c4f488801248724894ae30f0a87c2dcf95e17b289bdead06751f4bb0`
- Callback corpus SHA-256: `55433e072e968681ed43fa82a8321437261659b2fdc36d9d175cefad326b0d4a`
- Callback module SHA-256: `50436e64eced0a557b4632429e497eb17abd7b24da217fa59aee15e2fa34a527`

## Laws

- `gotp.erts.otp29-lists-differential`
- `gotp.erts.otp29-lists-callback-differential`
- `gotp.erts.otp29-lists-export-coverage`

## Decision

See ADR `0049-vm-global-export-metadata`.
