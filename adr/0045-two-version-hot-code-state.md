# Hot code loading is a two-version state machine

- ADR: `adr:gotp.two-version-hot-code-state`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.beam.hot-code`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Represent loaded code as an immutable transition system with at most one
current and one old generation per module. Loading a replacement moves current
to old. Reject a third generation until old code is purged. Track execution
references by generation so soft purge refuses live old code and forced purge
reports and invalidates every affected reference.

Clone BEAM module images at transition and observation boundaries. This keeps
the value-state invariant independent of mutation through exported interop
structures. An ERTS adapter associates references with process identities and
uses an explicit exit capability to terminate each forced-purge process once.

## Consequences

The core two-version and soft-purge rules are total, deterministic, and free of
ambient effects. Release handling, `code_change` callbacks, live process
instruction-pointer integration, and literal-area reclamation remain explicit
work under the partial `system.hot-code` ledger capability.

## Evidence

`test:gotp.beam.hot-code-laws` proves the two-version bound, third-load
rejection, current/old promotion, active-reference soft-purge refusal,
forced-purge invalidation, and image non-aliasing over generated transition
sequences.

`test:gotp.erts.hot-code-laws` proves reference ownership, effect-free soft
purge, one exit per affected process, and the OTP `killed` forced-purge reason.
