# Release scripts are typed transactions split at point of no return

- ADR: `adr:gotp.typed-release-script-transactions`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.otp.release-script`
- Reference implementation: OTP `OTP-29.0.4` `release_handler_1.erl`

## Decision

Decode low-level relup instructions from Erlang terms into a closed Go+ enum.
Preserve purge methods, suspend timeouts, change direction, arbitrary extras,
sync identifiers, and MFA arguments. Clone every term crossing the parser
boundary.

Split transactions at the single `point_of_no_return`. Require staged object
code to be contiguous before that boundary, reject duplicate staging, and
prove every committed load refers to a staged module. Parse and validate the
entire post-commit instruction stream before any effect executes.

## Consequences

Malformed or reordered scripts become typed failures rather than release-time
panics. A capability-neutral executor validates before effects, rolls successful
preflight operations back in reverse order, forbids rollback after commit, and
returns restart requests as typed outcomes. Concrete old-process checks,
distributed synchronization, appup translation, and restart orchestration
remain separate implementation phases.

## Evidence

`test:gotp.otp.release-script-laws` covers the pinned instruction vocabulary,
transaction split, mode/timeout/MFA preservation, staging invariants, malformed
ordering, and parser totality over arbitrary bytes.

`test:gotp.otp.release-executor-laws` proves validate-before-effect ordering,
reverse preflight rollback, no post-commit rollback, rollback-failure evidence,
and explicit restart outcomes.

## ERTS execution boundary

Artifact `gotp.erts.release-runtime` adapts validated release instructions to
the two-version hot-code runtime. Object-code staging, loading, and purging are
owned by that adapter. Process suspension and code change, application
stop/start, distribution synchronization, arbitrary MFA application, and
emulator restart remain explicit injected capabilities so release execution
cannot acquire ambient authority.

The adapter preserves `release_handler`'s transaction boundary: staged object
code can be rolled back before `point_of_no_return`; failures after that point
are reported without pretending that committed VM effects were reversed.
