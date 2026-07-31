# Connected terms use one versionless ETF prefix decoder

- ADR: `adr:gotp.versionless-etf-connected-terms`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable units: `code:gotp.etf.versionless-prefix`, `code:gotp.distribution.connected-terms`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Extend the canonical ETF decoder with an explicit operation that decodes one
versionless term, resolves `ATOM_CACHE_REF` through immutable per-message atom
references, and reports consumed source bytes. Keep ordinary ETF decode exact
and versioned.

Use that operation after a transactional distribution header to decode exactly
one control term and zero or one payload term. Reject trailing third terms and
preserve packet-4 zero-length ticks as a closed Go+ frame alternative.

## Consequences

Distribution does not fork ETF parsing and nested cache references work in all
term positions already supported by the canonical codec. Outbound encoding is
currently valid but deliberately emits an empty atom-cache header. Typed
control-message validation, outbound cache selection, and fragmented headers
remain incomplete.

## Evidence

`test:gotp.etf.versionless-prefix-laws` covers nested references, exact source
consumption, bounds, and malformed-input totality.
`test:gotp.distribution.connected-term-laws` covers cached controls, optional
payloads, ticks, and exact term count.
