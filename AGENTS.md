# AGENTS.md - GoTP

GoTP is a Go+-authored, Go-hosted BEAM/ERTS and OTP implementation.

- Author runtime semantics in `.gp`; commit generated `*_gp.go`.
- Author tests in `_test.gp`; commit generated `_gp_test.go`. Go's `testing`,
  `testing/quick`, fuzzing, race detector, coverage, and compatible property
  libraries remain the execution substrate.
- Prefer closed enums, exhaustive `match`, `result.Result`, and
  `option.Option` over tag fields, sentinel values, and `(value, bool, error)`.
- Raw Go errors belong only at explicit foreign boundaries; convert them to a
  package failure algebra immediately.
- Compatibility is pinned to `OTP-29.0.4`; master is a rolling audit only.
- The MIT core must not absorb Apache-2.0 OTP sources without an adjacent
  provenance record and license.
- The reference interpreter defines semantics. Optimized and JIT paths must
  compare against it.
- Foreign BEAM, ports, NIFs, drivers, cgo, assembly, and `unsafe` must remain
  visible in proof manifests.
- Never claim an inventory row complete from a symbol count or passing smoke
  test. Require upstream differential and property evidence.
- Do not publish tags without explicit approval.
