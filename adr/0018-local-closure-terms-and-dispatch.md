# ADR 0018: Local closures are immutable terms with module-aware dispatch

## Status

Accepted.

## Context

BEAM modules store local lambda metadata in `FunT`. OTP 29 `lists:concat/1`
constructs `thing_to_list/1` with `make_fun3`, validates it with `is_function2`,
and invokes it through `call_fun2`. Modeling closures as tuples would break term
kind order, exact equality, ETF evolution, and opcode validation.

## Decision

GoTP adds a sealed `FunTerm` carrying module, function name, visible arity,
entry label, function-table index, unique value, and an immutable captured
environment. Construction, projection, and cloning recursively clone captured
terms. Exact equality includes function identity and environment. Total term
order places funs between references and ports.

The BEAM layer decodes `FunT` through bounded `FunctionDecodeLimits`. Every
module image owns a cloned function-template table. `make_fun3` resolves and
clones its encoded capture list. `call_fun` and `call_fun2` check visible arity,
place captures after visible arguments, push a module-aware return frame, and
activate the closure's module and label. `is_function` and `is_function2` use
the fun projection rather than representation inspection.

Function calls consume one dispatch reduction. Closure construction and type
tests are reduction-free.

## Incomplete boundary

This decision covers local `FunT` closures. ADR 0019 adds old, new, and exported
ETF fun encodings. Assigning creator/code identity to newly created VM closures,
hot-code fun versioning, and purging rules remain required for OTP parity.

## Traceability

- Specification: `spec/local-closures.md`
- Source units: `gotp.beam.function-table`, `gotp.term.fun`,
  `gotp.vm.function-instructions`
- Laws: `gotp.beam.function-table-laws`, `gotp.term.fun-laws`,
  `gotp.vm.function-instruction-laws`, `gotp.erts.pinned-otp-closure-laws`
