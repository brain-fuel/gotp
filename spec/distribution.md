# Distribution authentication and ordered envelope specification

- Specification: `spec:gotp.distribution-foundation`
- Decision: `adr:gotp.distribution-foundation`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Authentication

Node names are validated Erlang atoms. Challenge entropy is an explicit
capability returning a 32-bit value. Initiator and acceptor authenticate with
independent incoming and outgoing cookies. A digest is MD5 of cookie text
followed by decimal challenge text, as specified by the OTP distribution
protocol. Digest checks use constant-time comparison.

Handshake progress is represented by distinct pending types. Reply acceptance
requires the acceptor's pending state; acknowledgement acceptance requires the
initiator's pending state. A successful connection exposes the intersection of
the nodes' distribution flags.

## Ordered envelopes

An envelope contains source PID, destination PID, and an immutable message.
The channel emits monotonically sequenced canonical ETF frames and accepts only
the exact next sequence. Replay, gaps, malformed ETF, and malformed envelopes
are rejected without advancing receive state. Byte and term values are cloned
at ownership boundaries.

## Incomplete boundary

This semantic foundation is not OTP wire interoperability. EPMD, sockets, TLS,
the packet-2 handshake encoding, packet-4 connected mode, distribution headers,
atom caches, control-message tags, fragmentation, tick handling, simultaneous
connect resolution, remote links/monitors, and hidden-node behavior remain.

## Evidence

`code:gotp.distribution.handshake` implements authentication and flag
negotiation. `code:gotp.distribution.ordered-channel` implements ordered ETF
envelopes. `test:gotp.distribution.handshake-laws` and
`test:gotp.distribution.ordered-channel-laws` cover the stated laws.
