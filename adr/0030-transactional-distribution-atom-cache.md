# Distribution atom-cache headers update transactionally

- ADR: `adr:gotp.transactional-distribution-atom-cache`
- Parent specification: `spec:gotp.distribution-foundation`
- Deployable unit: `code:gotp.distribution.atom-cache-header`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Represent the connection atom cache as eight 256-entry segments and each
message header as at most 255 ordered references. Parse and validate against a
private cache snapshot, then publish all updates together only when the entire
header succeeds. Encode with the same transactional rule.

Use the OTP half-byte flag layout exactly, including the extra long-atoms
nibble. Validate new UTF-8 atom text through the immutable GoTP term core and
return resolved atom names separately from persistent cache storage.

## Consequences

Malformed or truncated network input cannot poison later cache references.
Access is serialized per connection and returned atom/reference slices do not
alias cache state. ETF `ATOM_CACHE_REF` decoding and connected control/payload
term splitting remain separate integration work.

## Evidence

`test:gotp.distribution.atom-cache-header-laws` covers golden wire layout,
persistent references, long atoms, trailing term bytes, rollback, and total
malformed-input decoding.
