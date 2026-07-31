# Production NIF and driver entry points are explicit compatibility requirements

- ADR: `adr:gotp.pinned-native-loadable-entries`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-native-entries`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Extract `ERL_NIF_INIT` and `DRIVER_INIT` declarations from the 860 production
native source units. For each NIF initializer, resolve its referenced
`ErlNifFunc` arrays and inventory every exported Erlang name and arity together
with scheduler flags. Preserve load, reload, upgrade, and unload hooks on the
module requirement.

Conditional branches form a union. Identical semantic entries deduplicate;
conflicting definitions fail generation. Singular and plural test/example
trees are excluded by the upstream source inventory, and the exact source set
is content-digest pinned.

## Consequences

The ledger gains 296 production loadable requirements: 15 NIF modules, 279 NIF
functions, and 2 drivers. This inventories the native modules OTP loads and the
Erlang-callable surface they expose. It does not establish implementation
behavior, public NIF/driver C ABI completeness, platform-specific loading, or
resource and scheduler safety.

## Evidence

`test:gotp.compat.otp-native-entry-laws` proves exact kind counts, source
digest, ordering, complete ledger coverage, conditional deduplication,
lifecycle and scheduler metadata, comment exclusion, conflicting-definition
rejection, and malformed-input totality.
