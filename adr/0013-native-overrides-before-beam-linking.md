# ADR 0013: Resolve native overrides before BEAM module exports

## Status

Accepted.

## Context

OTP exports can name runtime-native functions while retaining a BEAM body that
only calls `erlang:nif_error/1`. The pinned OTP 29 `lists:reverse/2` export is
one such body. Treating every exported label as the authoritative implementation
therefore executes a fallback stub rather than OTP semantics.

## Decision

External-call effects return a distinct `ExternalCallUnbound` outcome. Dispatch
first asks the explicitly granted native registry. A returned value or rejection
is authoritative; only `ExternalCallUnbound` falls through to the immutable
linked-module export table. With no native capability, linked lookup occurs
directly. Ordinary linked calls save both program counter and module image;
tail calls transfer without adding a frame.

`ModuleSet` owns an immutable module-name index and constructs a process whose
machine receives cloned linked images. Runtime-native bindings remain explicit
through `CallRegistry`; no package-global registry is introduced.

## Consequences

- Native OTP overrides cannot accidentally execute their BEAM fallback stubs.
- Genuine native rejection is not confused with absence of a binding.
- Cross-module execution remains available when a registry has only a partial
  native surface.
- Adding an OTP native function requires a binding and conformance law, rather
  than an implicit special case in the interpreter.

## Traceability

- Specification: `spec/module-linking.md`
- VM source unit: `gotp.vm.module-continuation`
- ERTS source units: `gotp.erts.module-set`, `gotp.erts.otp-call-registry`
- Laws: `gotp.vm.module-continuation-laws`, `gotp.erts.module-set-laws`,
  `gotp.erts.otp-call-registry-laws`
