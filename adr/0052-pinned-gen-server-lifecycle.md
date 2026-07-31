# ADR 0052: Execute a pinned gen_server lifecycle through kernel effects

## Status

Accepted.

## Context

The request-ID corpus proved isolated `gen_server` exports but did not prove
that the pinned module could coordinate real processes. OTP 29 synchronous
calls depend on monitor-backed aliases, receive markers, closure environment
arity, monotonic time, loaded-function introspection, and exact process exit
reasons.

## Decision

Execute the unmodified OTP 29.0.4 `gen_server.beam` with a pinned callback
module. Model receive markers and external-function lookup as explicit VM host
effects. Model monitor aliases and exact process exit reasons in the kernel
rather than adding behavior-specific branches to `gen_server` execution.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable semantics
are traced by assay IDs `gotp.erts.otp29-gen-server-lifecycle`,
`gotp.kernel.monitor-alias-lifecycle`, and
`gotp.erts.receive-marker-cursor`. The corresponding Go+ sources are the
authoritative code links; generated `*_gp.go` files are deterministic build
artifacts.

## Consequences

The lifecycle establishes partial evidence only for declarations exercised by
the corpus. Timeout, named registration, linking, start-monitor, continuation,
code-change, multi-call, distributed, and failure/restart paths remain open.
