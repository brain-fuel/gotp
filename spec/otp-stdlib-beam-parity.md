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
- `gotp.erts.otp29-maps-differential`
- `gotp.erts.otp29-maps-callback-differential`
- `gotp.erts.otp29-maps-export-coverage`

## Maps evidence

The unmodified OTP `maps.beam` supplies all higher-level algorithms. GoTP
provides the emulator-owned native map operations, `erts_internal:map_next/3`,
`erts_internal:cmp_term/2`, and exported-fun dispatch expected by that module.

- `maps.beam` SHA-256: `15be7e753bb0b3e7d7a21d4cc058a7e7ea6755581e3a4886a559f006ebc1d7b6`
- Non-callback corpus SHA-256: `084d493eab49d0bdda7e060ae61a55ccbb7b7eb31cbc79b9b1fe82d997641d47`
- Callback corpus SHA-256: `d0f78ba67c2d41f5804a520e79d8951c03553a3b2679c25fb4119dd905ad3d63`
- Callback module SHA-256: `a4ce72a1e9497adc7b3c8edfde74788ca6cbb4a4f1190363170366a4163eef78`

## Decision

See ADRs `0049-vm-global-export-metadata` and
`0050-exported-functions-use-external-dispatch`.

## List-backed collection evidence

The unmodified `proplists`, `ordsets`, and `queue` modules execute in linked
module sets with pinned `lists`, `maps`, and `sets` dependencies as required.
Documented unordered results compare by membership; every ordered result,
return value, and exception remains exact.

- `proplists` corpus: `sha256:0c51cfdbe21944d5ac7c86f05b70d0338273316e2d5a3b3e1d216e6448b7727f`
- `ordsets` corpus: `sha256:36478744a455a3838cbfc22d8b41d6529b101873dc149883e4b081d66d6bd743`
- `ordsets` callback corpus: `sha256:326efe35a809b3fa490c2a4931a253739c3fcf85783e7160e3f43302e4ec53c6`
- `queue` corpus: `sha256:ffbbdde72db7e5c355b1e95de987848e4f9f485be8d3b25a30fe573335c562cf`
- `queue` callback corpus: `sha256:f80edf1d4484b834c1b1b753587901f1ce95d59ba7d9f5d4a6ce8b3e5596c98d`

## Balanced-tree evidence

The opaque set and tree values in these corpora are produced by OTP and passed
through ETF unchanged. This tests GoTP against the pinned representation as
well as the public behavior.

- `gb_sets` corpus: `sha256:baebc4e244a273240ed379539f14d51b627eba3ce253b36e4c6861d733c29ef0`
- `gb_sets` callback corpus: `sha256:15b68c00cf4f96d5e604af76ed8d01a0e5480a8cf6afb26ef9b041211dc526d7`
- `gb_trees` corpus: `sha256:909bcb16c572321f2bb4792cf2f2fc4294eac7712c420fb101a5c93f1f24f318`
- `gb_trees` callback corpus: `sha256:4e764c8238d7b8e28d0568a66fbe600c16774665de8a8be4b32b6f554e08a4e3`

## Gen-server foundation

The pinned `gen_server.beam` currently executes request-ID collection and
introspection exports. ETF reference terms use an explicit static node resolver.

The pinned lifecycle callback additionally executes `start/3,4`,
`start_link/3,4`, `start_monitor/3,4`, `call/2,3`, `cast/2`, `reply/2`,
`stop/1`, and `system_code_change/4` through the ordinary scheduler. It
exercises `init/1`, `handle_call/3`, `handle_cast/2`, `handle_continue/2`,
`handle_info/2`, `code_change/3`, and `terminate/2` across normal and adverse
paths. Evidence includes monitor-backed aliases, zero-timeout late-reply
suppression, callback-crash reasons, linked-parent termination, local named
registration and duplicate starts, and suspended system code change.

The same pinned module executes `enter_loop/3,4,5` from correctly initialized
`proc_lib` processes. The isolated corpus covers anonymous, local, global, and
via names; timeout, hibernate, and continue actions; calls, casts, unsolicited
messages, system suspend/change/resume, termination, and linked-parent exits.
It also preserves exact failures for non-`proc_lib` callers, unregistered or
wrongly registered names, and invalid initial actions. A stateful law compares
randomized post-entry traces with an ordinarily started `gen_server`. These
rows remain partial because the complete Erlang term domain and all malformed
callback/action combinations have not been exhausted.

The diagnostic slice executes `format_log/1,2` and `format_status/2` through
OTP's pinned formatter closure. Its isolated corpus compares rendered bytes for
legacy, multi-line, single-line, depth-limited, character-limited, Unicode,
termination, crash, and missing-handler reports. Live status covers normal and
suspended servers plus modern `format_status/1` and legacy `format_status/2`
callbacks. Stateful laws prove deterministic output and equivalent formatted
status for ordinary and `enter_loop` servers. Process-dictionary enumeration
and anonymous PID headers are normalized; exhaustive report, option, callback,
and malformed-term domains remain open.

- Lifecycle corpus: `sha256:107c3a6a92d360f45746c41b547fe0d131b497d595e09b4397630fcab180b641`
- Callback module: `sha256:ad5045f2062900129aa7eb74cf3d9cb82c0cb79cac7af0d6f13348d5b6dc7956`
- Lifecycle law: `gotp.erts.otp29-gen-server-lifecycle`
- Record-update law: `gotp.vm.update-record-laws`
- Monitor-alias law: `gotp.kernel.monitor-alias-lifecycle`
- Receive-marker law: `gotp.erts.receive-marker-cursor`

The asynchronous request slice executes `send_request/2,4`,
`wait_response/2,3`, `receive_response/2,3`, and `check_response/2,3` against
OTP-oracle outcomes. It covers direct and request-collection responses,
retryable wait timeout, abandoned receive timeout with late-response
suppression, exact crashed-server errors, local names, unrelated-message
checks, and multiple outstanding requests delivered out of issue order.

- Asynchronous corpus: `sha256:62014e459c5f61dd37c65dbd92d8db0d5a62f5a91e08d01f1cb4da19b81b6e38`
- Callback module: `sha256:24d5c8c2676b17331481e07f1334dd35de17131680e3dc3de69913f1fcb491db`
- Differential law: `gotp.erts.otp29-gen-server-async-requests`
- Stateful order law: `gotp.erts.gen-server-request-collection-order`

The distributed multi-call slice executes `multi_call/2,3,4` on a deterministic
three-kernel virtual cluster and compares against an OTP oracle using two real
peer nodes. It covers healthy local and distributed servers, mixed missing
registrations, unavailable nodes, callback crashes, zero-timeout late-response
suppression, duplicate and empty node lists, reply ordering, bad-node
classification, and mailbox cleanup.

- Multi-call corpus: `sha256:408298f0caee48d5f449e757017a5902eff380fe0509e31e9f1ac3466d56a444`
- Callback module: `sha256:e0a16ac918c1667dc70c6d41772b95cd3b69742dfa10e3cb608fc36d8f1e071b`
- Differential law: `gotp.erts.otp29-gen-server-multi-call`
- Stateful classification/order law: `gotp.erts.gen-server-multi-call-classification-order`
- Virtual-cluster unit: `gotp.erts.virtual-cluster`

This is not lifecycle parity for the entire module. Enter-loop, formatting,
state replacement, administrative termination, and the exhaustive declared
input domains remain open.

## Gen-server decision

See ADRs `0052-pinned-gen-server-lifecycle` and
`0053-gen-server-adverse-lifecycle-matrix`, and
`0054-gen-server-asynchronous-request-lifecycle`, and
`0055-gen-server-distributed-multi-call`.
