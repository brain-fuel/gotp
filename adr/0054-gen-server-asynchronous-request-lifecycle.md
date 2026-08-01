# ADR 0054: Prove asynchronous gen_server requests as live lifecycles

## Status

Accepted.

## Context

Detached request-ID collection operations do not prove that asynchronous calls
interact correctly with monitor aliases, process death, timeout cleanup, named
registration, mailbox ordering, or multiple outstanding requests.

## Decision

Execute all eight asynchronous request exports from the unmodified OTP 29.0.4
`gen_server.beam` through isolated callback scenarios. Compare stable semantic
outcomes to an OTP-generated corpus. Supplement examples with a stateful
property law that releases live requests in randomized permutations and checks
both response-label order and collection cardinality after every deletion.

The specification is `spec/otp-stdlib-beam-parity.md`. Deployable behavior is
traced by assay artifacts `gotp.erts.otp29-gen-server-async-requests` and
`gotp.erts.gen-server-request-collection-order`; generated manifests resolve
those identifiers without fragile source line links.

## Consequences

Existing monitor-alias and selective-receive semantics support this slice
without an API-specific runtime branch. The eight declarations have partial,
not exhaustive, compatibility evidence. Distributed server references and the
complete invalid-input domains remain outside this milestone.
