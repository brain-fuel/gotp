# Two-version hot code loading

- Decision: `adr:gotp.two-version-hot-code`
- Deployable unit: `code:gotp.erts.hot-code-server`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Generations

Each module has one current and at most one old generation. Loading a second
version moves current to old and installs a new current generation. A third load
is rejected until old code is explicitly purged, independent of whether old code
currently has leases.

Generation identity includes module name, monotonic number, and module digest.
Acquisition always leases current code. Leases resolve their exact generation
and release idempotently.

## Purging

Soft purge removes old code only when no leases reference it and otherwise
reports the active count. Forced purge removes old code regardless of leases;
subsequent resolution through those leases fails as purged. The process-killing
adapter for forced purge remains future integration.

## Incomplete boundary

Automatic VM process leases, local-call old-code execution, `code_change`
callbacks, release handlers, appup/relup, on_load, native code, distributed code
loading, and OTP code-server API compatibility remain required.

## Evidence

`test:gotp.erts.hot-code-server-laws` covers two-version transitions, third-load
rejection, lease-aware soft purge, forced invalidation, and concurrent idempotent
release.
