# Pinned OTP applications, modules, and production sources are explicit compatibility rows

- ADR: `adr:gotp.pinned-otp-source-inventory`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-upstream-inventory`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Derive a deterministic manifest from the complete Git tree at pinned commit
`1259612946cb36a8bf9614b289090bb32fbcbeb2`. Inventory every shipped OTP
application manifest, every Erlang source module under application `src` trees
and ERTS preloaded sources, and every production native, Java, generator, and
public-header unit. Require exactly 36 applications, 1,268 modules, and 981
source units, strict identity ordering, unique membership, and matching
provenance.

Represent every application, module, and source unit with an explicit
compatibility-ledger row. Generate the manifest from a supplied GitHub tree
payload through the Go+ `otpinventory` command; network access is outside the
deterministic transform.

## Consequences

The source rules exclude singular and plural example/test trees. Broad partial
rows cannot support
an OTP parity claim. Source-unit inventory is complete for the stated path
rules, but global `inventory_complete` remains false until public declarations,
protocols, tools, generated outputs, and behavioral requirements are
independently inventoried.

## Evidence

`test:gotp.compat.otp-upstream-inventory-laws` proves pinned counts, source-kind
partitioning, sorting, membership, deterministic rebuilding, complete ledger
coverage, malformed-input totality, and stale-provenance rejection.
