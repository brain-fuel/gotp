# Module linking and runtime-native overrides

## Contract

An external MFA resolves in this order:

1. An explicitly granted runtime-native call registry.
2. The export table of an immutable linked BEAM module image when the registry
   reports that the MFA is unbound.
3. A deterministic unbound-external-function failure.

A native rejection is terminal and never falls through. With no native-call
capability, linked BEAM resolution remains available and requires no host
effect.

An ordinary linked call saves the caller module image and next instruction.
`return` restores both. A linked tail call replaces the active module image and
reuses the existing continuation frame.

`ModuleSet` rejects nil modules and duplicate module names. Process construction
selects one root module and links every other module by name without introducing
mutable global state.

## Evidence

- `gotp.vm.module-continuation-laws` proves ordinary return restoration, tail
  transfer, native precedence, and unbound-native linked fallback.
- `gotp.erts.module-set-laws` proves indexed process construction and duplicate
  rejection.
- `gotp.erts.otp-call-registry-laws` executes pinned OTP 29 `lists.beam` and
  proves `lists:reverse/1` reaches the runtime-native `lists:reverse/2` override.

## Decision

See ADR `0013-native-overrides-before-beam-linking`.
