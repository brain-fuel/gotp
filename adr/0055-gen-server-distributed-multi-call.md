# ADR 0055: Execute gen_server multi-call on deterministic virtual nodes

## Status

Accepted.

## Context

Distribution codecs and inbound controls alone do not prove that BEAM code can
send to `{Name, Node}`, install tagged remote monitors, receive replies through
remote aliases, enumerate connected nodes, or classify partial failures.
`gen_server:multi_call/2,3,4` requires all of those behaviors together.

## Decision

Introduce a kernel-level remote transport capability and an ERTS virtual
cluster that cooperatively runs multiple kernels. Route remote PID, registered
name, and alias sends through that capability. Preserve tagged monitor objects
and reasons across remote exits. Provide node identity, connected-node
enumeration, and cancelable message timers as general runtime semantics.

Execute the unmodified OTP 29.0.4 `gen_server.beam` on a three-node virtual
cluster. Compare it with a deterministic corpus produced by an official OTP
runtime using two real peer nodes. Add a stateful property law over randomized
connectivity, registration, target duplication/order, and cleanup.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by assay artifacts `gotp.erts.virtual-cluster`,
`gotp.erts.otp29-gen-server-multi-call`, and
`gotp.erts.gen-server-multi-call-classification-order`.

## Consequences

The runtime gains reusable in-memory multi-node execution without a
`gen_server`-specific transport branch. The three declarations have strong
cross-node partial evidence, but exhaustive invalid argument domains and every
real network partition timing remain open.
