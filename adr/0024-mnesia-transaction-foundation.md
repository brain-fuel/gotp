# ADR 0024: Mnesia begins with cloned serializable workspaces

## Status

Accepted.

## Context

Mnesia transaction semantics require all writes to become visible atomically or
not at all. Directly layering independent ETS calls would expose partial writes
and make rollback impossible.

## Decision

The initial Mnesia core clones database state into a transaction-owned workspace
under a serialization lock. A sealed decision commits or aborts the workspace.
Transaction handles carry an explicit active state and reject use after the
callback returns. Terms are cloned at every storage and observation boundary.

The coarse lock establishes strict serializability now. Later MVCC, distributed
locking, and persistence may replace it only with differential evidence for
rollback, visibility, conflict, ordering, and recovery semantics.

Snapshots reuse GoTP's canonical ETF codec rather than introducing a Mnesia-only
serializer. A versioned term is deterministically ordered before encoding;
restore validates temporary state and performs one final state swap. Filesystem
atomicity remains a separate explicit capability.

Local persistence delegates replacement durability to Go+ `std/fsatomic` rather
than reproducing temporary-file, sync, rename, cleanup, and directory-sync
logic. Foreign filesystem errors are converted at the boundary with
`std/result.Of`; decoded state still passes snapshot validation before commit.

## Traceability

- Parent specification: `spec/mnesia.md`
- Compatibility item: `stdlib.mnesia`
- Source unit: `gotp.otp.mnesia-transactions`
- Snapshot source unit: `gotp.otp.mnesia-snapshots`
- Persistence source unit: `gotp.otp.mnesia-persistence`
- Laws: `gotp.otp.mnesia-transaction-laws`
- Snapshot laws: `gotp.otp.mnesia-snapshot-laws`
- Persistence laws: `gotp.otp.mnesia-persistence-laws`
- Reference: Erlang/OTP `OTP-29.0.4`, `mnesia`
