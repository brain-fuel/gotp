# Distribution wire codecs are bounded and handshake-state directed

- ADR: `adr:gotp.distribution-wire-codecs`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable unit: `code:gotp.distribution.handshake-wire`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Encode and decode OTP 25+ distribution handshake messages as packet-2 frames,
and connected transport payloads as packet-4 frames. Decode the reused `'N'`
tag through separate name and challenge functions because the handshake state,
not the tag alone, determines its layout. Bound every allocation by the framing
width and clone bytes across API boundaries.

Node-name and challenge messages accept trailing extension bytes as required by
OTP. Fixed-layout complement, reply, and acknowledgement messages reject
extensions. Status is a closed Go+ enum, including dynamic naming and the
alive-handshake continuation response.

## Consequences

Wire layouts can now be differentially tested and connected to an explicit
stream capability. EPMD, stream I/O, mandatory-flag policy, distribution
headers, atom caches, connected control messages, and full Erlang node
interoperability remain incomplete.

## Evidence

`test:gotp.distribution.handshake-wire-laws` covers golden OTP layout,
round trips, extension handling, ticks, ownership isolation, exact-length
rejection, and bounded malformed-input totality.
