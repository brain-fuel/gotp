# Port capability boundary

- Decision: `adr:gotp.port-capability-boundary`
- Deployable unit: `code:gotp.erts.port-manager`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Drivers and sessions

A port can only be opened through an explicit driver capability. Opening returns
a complete command/close session or a typed rejection. The manager assigns a
monotonic BEAM port identity using configured node and creation values.

The opening process is the connected owner. Only that owner can command or
close the port, and owner exit closes every owned port. Command input and output
are cloned across the driver boundary. Each port serializes command and close;
concurrent close attempts invoke the driver at most once.

## Incomplete boundary

Kernel process integration, asynchronous driver output, busy-port flow control,
packet/line modes, exit-status messages, registered names, links, remote ports,
OS subprocess drivers, dynamic drivers, NIF loading, dirty schedulers, resource
objects, and OTP driver/NIF ABI compatibility remain required.

## Evidence

`test:gotp.erts.port-manager-laws` covers identity, ownership, cloned payloads,
owner-exit cleanup, driver validation, and concurrent close serialization.
