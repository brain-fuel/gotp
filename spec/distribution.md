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

## Wire framing

OTP 25+ name, status, challenge, complement, reply, and acknowledgement
messages use bounded packet-2 codecs with big-endian fields. Connected payloads
use bounded packet-4 framing, including zero-length tick packets. Parsing of the
reused `N` tag is handshake-state directed. Name and challenge extension bytes
are accepted; fixed-layout authentication messages are exact.

## Atom-cache headers

A connection cache contains eight segments of 256 entries. Normal distribution
headers resolve at most 255 ordered references and use OTP's half-byte flag
layout, including short and long UTF-8 atom lengths. Header updates commit as a
group only after every reference validates; malformed input leaves prior cache
state unchanged.

## Connected terms

After the header, exactly one versionless ETF control term and at most one
versionless payload term are decoded. `ATOM_CACHE_REF` resolves through the
header's immutable per-message references in every nested term position. Prefix
decoding reports consumed bytes; a third term is rejected. Empty packet-4
payloads remain explicit tick frames.

## Control messages

Every documented non-obsolete control opcode through 36 maps to a closed Go+
code. Construction validates exact arity and PID, name, reference, MFA, list,
spawn-flag, and unlink-ID constraints. Payload presence is opcode-specific;
spawn argument payloads must be proper lists. Obsolete `UNLINK` and unassigned
opcodes are rejected before kernel dispatch.

## Negotiated modes

Sender-bearing, payload-exit, spawn, alias, and unlink-ID operations require
their negotiated flags. Receiving the first `SEND_SENDER` family operation or
payload-exit family operation advances a direction-local state monotonically;
legacy operations in that family are rejected afterward. Validation and state
advance are serialized and transactional.

## Kernel dispatch

Validated controls dispatch through ERTS into exact kernel operations for PID
send, remote link, exit, remote monitor, remote demonitor, remote DOWN, alias
send, and remote unlink. Local termination queues ordered outbound EXIT/DOWN
signals for remote relationships. Outcomes distinguish application, missing destinations,
required replies, and deferred semantics. `UNLINK_ID` returns a reversed-endpoint
`UNLINK_ID_ACK` control. Deferred controls are never approximated.

Registered process names are kernel-owned validated atoms with one-to-one live
process ownership and exit cleanup. Registered sends and named monitors resolve
through that authority. Named monitor identity survives process exit in outbound
DOWN signals. Group-leader controls accept a valid remote leader and require a
live local member.

Locally initiated remote unlinks retain inactive per-process metadata until the
matching positive 64-bit acknowledgement arrives. Stale acknowledgements are
ignored, incoming LINK cannot reactivate an outstanding unlink, and crossed
UNLINK_ID operations preserve local metadata while producing their own ack.

Outbound controls use synchronized ordinary and required-reply lanes with FIFO
inside each lane. Incoming UNLINK_ID acknowledgements enter the priority lane
ahead of ordinary output; locally initiated UNLINK_ID enters ordinary output.
Terms are cloned at queue boundaries and encoded through negotiated policy.

## Incomplete boundary

This semantic foundation is not complete OTP wire interoperability. EPMD,
sockets, TLS, mandatory baseline-flag policy, node-link/seq-trace/spawn dispatch,
local registered BIF adapters, transport backpressure/fairness,
outbound atom cache selection, fragmentation, simultaneous
connect resolution, remote transport draining, and hidden-node behavior remain.

## Evidence

`code:gotp.distribution.handshake` implements authentication and flag
negotiation. `code:gotp.distribution.ordered-channel` implements ordered ETF
envelopes. `code:gotp.distribution.handshake-wire` implements packet framing
and handshake layouts. `test:gotp.distribution.handshake-laws`,
`test:gotp.distribution.handshake-wire-laws`, and
`test:gotp.distribution.ordered-channel-laws` cover the stated laws.
`code:gotp.distribution.atom-cache-header` and
`test:gotp.distribution.atom-cache-header-laws` cover transactional cache
headers.
`code:gotp.etf.versionless-prefix`, `code:gotp.distribution.connected-terms`,
`test:gotp.etf.versionless-prefix-laws`, and
`test:gotp.distribution.connected-term-laws` cover connected term boundaries.
`code:gotp.distribution.control-messages`,
`code:gotp.distribution.typed-connected`, and
`test:gotp.distribution.control-message-laws` cover typed controls.
`code:gotp.distribution.negotiated-controls` and
`test:gotp.distribution.negotiated-control-laws` cover feature modes.
`code:gotp.erts.distribution-dispatch`,
`code:gotp.kernel.remote-monitor-signals`,
`code:gotp.kernel.remote-process-signals`, and
`test:gotp.erts.distribution-dispatch-laws` cover kernel effects.
`code:gotp.kernel.registered-processes` and
`adr:gotp.registered-process-identity` cover shared name and group identity.
`code:gotp.kernel.remote-unlink-protocol` and
`adr:gotp.remote-unlink-state-machine` cover unlink acknowledgement state.
`code:gotp.distribution.outbound-controls`,
`code:gotp.erts.distribution-outbound`, and
`adr:gotp.priority-distribution-output` cover ordered outbound controls.
