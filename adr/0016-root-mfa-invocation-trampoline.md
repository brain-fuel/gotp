# ADR 0016: Root MFA invocation uses the external dispatch path

## Status

Accepted.

## Context

Starting a machine directly at an exported BEAM label bypasses runtime-native
export overrides. OTP modules retain fallback bodies for native exports; pinned
OTP 29 `lists:member/2`, for example, calls `erlang:nif_error/1` when entered by
label. Cross-module calls already resolve native bindings before linked BEAM
exports, so root and nested calls otherwise have observably different semantics.

## Decision

`LoadedModule.Invoke` and `ModuleSet.Invoke` create a two-instruction immutable
root trampoline: a label followed by `call_ext_only` to the requested MFA. The
target module image, or complete module set, is linked beneath that root. The
existing external dispatcher therefore applies native-first resolution and
linked-BEAM fallback uniformly at process entry and at every nested call.

Arguments are cloned into X registers before execution. Arity is derived from
the argument vector and checked against the exported MFA. Loaded module register
and step-limit configuration is preserved. Invocation returns a schedulable
`VMProcess`; no host work or module code runs during construction.

Direct `Start(label)` remains available as a low-level VM mechanism and does not
promise native-export resolution.

## Traceability

- Specification: `spec/module-invocation.md`
- Source unit: `gotp.erts.module-invocation`
- Laws: `gotp.erts.module-invocation-laws`, `gotp.erts.otp-pure-bif-laws`
