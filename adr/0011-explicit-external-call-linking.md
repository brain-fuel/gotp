# ADR 0011: Link external calls through explicit immutable registries

## Status

Accepted

## Context

BEAM import indexes identify external MFAs, but resolving them through a global mutable table would hide authority, prevent deterministic replay, and couple VM correctness to ambient process state.

## Decision

Module loading copies `ImpT` into zero-based immutable machine configuration. The VM grants external dispatch through a closed capability sum and invokes an MFA-aware effect only after validating operand arity, import presence, initialized arguments, and call authority.

ERTS registries are constructed once from validated structural MFA bindings. Linked process construction is explicit; existing unlinked constructors remain unable to perform external calls. Registry implementations receive cloned arguments and return immutable runtime terms through a closed outcome sum.

The VM models ordinary and tail external returns independently. `call_ext_last` performs frame deallocation before dispatch, matching the pinned generic instruction contract. Dispatch consumes one reduction.

## Consequences

Native and BIF-style calls are deterministic, capability-scoped, and testable without global runtime mutation. Missing or rejected imports fail structurally.

Cross-module BEAM continuation transfer, trapping calls, NIF loading, and exception propagation remain separate work and prevent a conformant instruction/linker claim.

## Traceability

- Specification: `spec/external-import-calls.md`
- VM code: `gotp.vm.external-call-capability`
- VM law: `gotp.vm.external-call-laws`
- ERTS code: `gotp.erts.call-registry`
- ERTS law: `gotp.erts.call-registry-laws`
