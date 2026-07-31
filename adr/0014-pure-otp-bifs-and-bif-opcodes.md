# ADR 0014: Pure OTP BIF registry and checked BIF instructions

## Status

Accepted.

## Context

OTP modules compile common arithmetic, list, conversion, equality, and tuple
operations to `bif*` and `gc_bif*` instructions. These instructions name entries
in the module import table and carry a failure label. Treating them as ordinary
external calls loses failure-label behavior; leaving them unsupported prevents
ordinary pinned modules such as `lists:sum/1` from executing.

## Decision

GoTP executes `bif0`, `bif1`, `bif2`, `gc_bif1`, `gc_bif2`, and `gc_bif3`
through one validated instruction shape. Sources are resolved and cloned,
runtime-native capability is mandatory, successful values are assigned to the
encoded destination, and rejected calls branch to the encoded nonzero failure
label. Label zero remains an exception boundary until structured BEAM exception
state is implemented.

The GC variants validate their live-register count. They do not trigger a Go
heap collection: GoTP terms are immutable values and the current machine does
not expose OTP's moving-heap root protocol.

The OTP registry supplies pure bindings for arithmetic, `div`, exact equality,
list append/subtract/length, integer/float/atom conversion, tuple element access,
tuple update, and `lists:reverse/2`. Integer arithmetic remains arbitrary
precision and mixed arithmetic promotes to float.

## Traceability

- Specification: `spec/pure-bifs.md`
- Source units: `gotp.vm.bif-instructions`, `gotp.erts.otp-pure-bifs`
- Laws: `gotp.vm.bif-instruction-laws`, `gotp.erts.otp-pure-bif-laws`,
  `gotp.erts.pinned-otp-lists-laws`
