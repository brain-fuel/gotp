# Remote unlink metadata persists until matching acknowledgement

- ADR: `adr:gotp.remote-unlink-state-machine`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable unit: `code:gotp.kernel.remote-unlink-protocol`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Represent an initiated remote unlink as inactive process-local link metadata
containing its positive 64-bit identifier. Repeated initiation returns the same
outstanding identifier. A matching acknowledgement removes metadata; stale,
duplicate, wrong-route, and wrong-identifier acknowledgements are ignored.

Ignore an incoming LINK while local inactive metadata exists. An incoming
UNLINK_ID removes an active link but leaves a crossed local outstanding unlink
unchanged, and always yields its required reversed-endpoint acknowledgement.

## Consequences

Crossed link/unlink races follow OTP's mandatory post-26 protocol instead of
collapsing to a boolean link. Pending operations are visible in process info and
discarded on process termination. Encoding locally initiated UNLINK_ID into an
outbound connection queue and transport-level acknowledgement prioritization
remain integration work.

## Evidence

`test:gotp.erts.distribution-dispatch-laws` covers stable identifiers, crossed
LINK and UNLINK_ID, stale and duplicate acknowledgements, matching completion,
and required replies.
