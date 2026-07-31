# Required distribution replies have an explicit priority lane

- ADR: `adr:gotp.priority-distribution-output`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable units: `code:gotp.distribution.outbound-controls`, `code:gotp.erts.distribution-outbound`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Queue immutable validated outbound controls in synchronized ordinary and
required-reply lanes. Drain required replies first and preserve FIFO order
within each lane. Clone controls and payload terms at enqueue and dequeue
ownership boundaries.

Translate locally initiated kernel unlink state into ordinary `UNLINK_ID`
output. Translate incoming unlink dispatch replies into priority
`UNLINK_ID_ACK` output. Encode dequeued controls through the negotiated codec so
feature and downgrade policy applies symmetrically outbound.

## Consequences

An acknowledgement is emitted before already queued ordinary signals, meeting
OTP's stronger same-peer ordering requirement. The global lane is intentionally
stronger than per-peer priority. Socket backpressure, batching, fair peer
scheduling, retransmission, and transport ownership remain incomplete.

## Evidence

`test:gotp.distribution.outbound-control-laws` covers priority, FIFO, cloning,
negotiated encoding, concurrency, and no loss.
`test:gotp.erts.distribution-outbound-laws` covers UNLINK_ID construction and
acknowledgement promotion ahead of existing output.
