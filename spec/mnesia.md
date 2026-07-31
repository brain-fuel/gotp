# Mnesia transaction foundation

- Decision: `adr:gotp.mnesia-transaction-foundation`
- Deployable unit: `code:gotp.otp.mnesia-transactions`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Transactions

Each transaction receives an isolated clone of database state while holding the
database serialization capability. Reads observe prior writes and deletes in
the same transaction. `DecideCommit` atomically replaces live state;
`DecideAbort` discards the complete workspace and preserves a cloned reason.

Keys and values are arbitrary cloned BEAM terms and use exact term equality.
Retained transaction handles become inactive after the callback returns, so a
caller cannot mutate committed state outside the transaction lifetime.

## Current isolation

Transactions are strictly serializable through a coarse database lock. This is
semantically stronger than optimistic interleaving but intentionally not the
eventual performance design. Dirty reads are explicit and still return clones.

## Snapshots

Snapshots are versioned canonical ETF terms. Tables sort by name and rows by
canonical encoded key, making bytes independent of map and insertion order.
Restore decodes and validates the complete image, including duplicate tables
and keys, into temporary state before atomically replacing live state. Codec
limits and node resolution remain explicit capabilities.

`SaveFile` passes canonical bytes to Go+ `std/fsatomic`, which writes and syncs
a temporary file, renames it over the target, and syncs the containing directory
where the platform permits. `LoadFile` reads bytes, then uses the same complete
temporary-state validation as in-memory restore. File-system errors become typed
persistence failures immediately through `std/result.Of`.

## Incomplete boundary

Distributed schemas and locks, replication, disc copies, transaction logs, checkpoints,
recovery, indexes, table types, nested transactions, retry/abort conventions,
subscriptions, backup/restore, fragmentation, and the remaining Mnesia API are
required for parity.

## Evidence

`test:gotp.otp.mnesia-transaction-laws` covers rollback, read-your-writes,
arbitrary-term keys, stale-handle rejection, and concurrent serializability.
`test:gotp.otp.mnesia-snapshot-laws` covers deterministic bytes, round trips,
canonical restoration, corrupt input, and failure atomicity.
`test:gotp.otp.mnesia-persistence-laws` covers atomic replacement, file round
trips, corrupt-file rollback, and foreign filesystem failures.
