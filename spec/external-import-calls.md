# External import calls

GoTP binds BEAM `ImpT` indexes to explicit MFA capabilities and executes OTP-29.0.4 `call_ext`, `call_ext_only`, and `call_ext_last` instructions.

## Contract

- Imports retain their zero-based OTP table index and structural `{module, function, arity}` identity.
- Registry construction validates module/function atoms, rejects duplicate MFA bindings, and rejects nil implementations.
- Registry lookup is immutable and deterministic; no process can consult ambient global dispatch state.
- Arguments are cloned from `x(0)` through `x(arity-1)` and returned values are cloned into `x(0)`.
- Instruction arity must equal the imported MFA arity.
- Every external dispatch consumes one reduction, matching OTP `DISPATCH_EXPORT`.
- `call_ext` returns to the following instruction; `call_ext_only` returns through the current continuation; `call_ext_last` first deallocates its declared frame and then returns through the current continuation.
- A process without explicit external-call authority fails closed.

## Current boundary

- Registry implementations are synchronous native/BIF-style effects.
- Cross-module BEAM calls do not yet transfer a continuation to another loaded module.
- NIF library loading, dirty schedulers, trapping BIFs, and exception-class propagation are not implemented.

## Executable evidence

- `gotp.vm.external-call-capability`
- `gotp.vm.external-call-laws`
- `gotp.erts.call-registry`
- `gotp.erts.call-registry-laws`

## Upstream trace

- OTP-29.0.4 `lib/compiler/src/genop.tab`: operand, continuation, tail-call, and deallocation contracts.
- OTP-29.0.4 `erts/emulator/beam/emu/macros.tab`: `DISPATCH_EXPORT` reduction behavior.
