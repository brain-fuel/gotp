# Root module invocation

## Contract

`LoadedModule.Invoke(Function, Arguments, Clock, Registry)` validates that the
module exports the derived `Function/Arity`, constructs a schedulable process,
and dispatches that root MFA through the same external-call path used by nested
BEAM calls.

`ModuleSet.Invoke(Module, Function, Arguments, Clock, Registry)` additionally
links every module in the immutable set, allowing the invoked function to
continue across module boundaries.

Dispatch order is:

1. A bound runtime-native implementation.
2. The linked module's BEAM export when the native registry reports unbound.
3. Deterministic unbound-MFA failure.

Native rejection is terminal and does not fall back. The invocation trampoline
is a tail call, so the target's return completes the process without an extra
continuation frame.

## Native membership

The OTP registry binds `lists:member/2`. It requires a proper list and uses exact
term equality, so integer `1` is not a member of `[1.0]`.

## Evidence

Pinned OTP 29 `lists.beam` laws prove root native override through `member/2`,
root linked-BEAM fallback through `last/1`, exact numeric membership, and
equivalent `ModuleSet.Invoke` behavior.

## Decision

See ADR `0016-root-mfa-invocation-trampoline`.
