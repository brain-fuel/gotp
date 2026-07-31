# ADR 0006: VM host effects require explicit capabilities

- Status: accepted
- Artifact: `adr:gotp.explicit-vm-host-effects`
- Specifies: `spec:gotp.vm-host-effects`
- Implemented by: `code:gotp.vm.host-effects`, `code:gotp.erts.vm-process`
- Verified by: `test:gotp.vm.host-effect-laws`, `test:gotp.erts.message-effect-laws`

## Context

BEAM `send/0` is effectful and consumes one reduction. Letting the VM access a
global kernel would hide authority, create a package cycle, and prevent pure VM
tests.

## Decision

VM continuation resumption accepts an explicit host capability algebra.
Capabilities and outcomes are exhaustive Go+ enums. Without a send capability,
`send/0` fails. The ERTS adapter supplies authority scoped to the current kernel
`Context`, converts term PIDs, and preserves Erlang's message-as-result rule.

## Consequences

Send effects are deterministic under a fake capability and integrate with real
kernel mailbox wakeup. Remote distribution, registered names, ports, aliases,
and full send failure semantics remain deferred.
