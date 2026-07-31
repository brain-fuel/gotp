# JInterface compatibility is inventoried from JVM binary descriptors

- ADR: `adr:gotp.pinned-jinterface-binary-api`
- Parent specification: `spec:gotp.otp-29-0-4-compatibility`
- Deployable unit: `code:gotp.compat.otp-java-api`
- Upstream baseline: Erlang/OTP `OTP-29.0.4`

## Decision

Compile all 57 pinned JInterface Java sources with Temurin `javac 21.0.12` and
inventory the 65 resulting JVM class files. Decode class files in Go+ and retain
every public or protected class, interface, field, constructor, and method.
Stable identities include class name, member name, JVM descriptor, and generic
signature; overloads therefore remain distinct.

Preserve checked exceptions, visibility, static/final status, synthetic and
bridge flags, and a digest of API-relevant class-file metadata. Pin both exact
source bytes and deterministic class output. Compilation is an explicit
`std/process` capability and occurs in a fresh temporary output directory.

## Consequences

The ledger gains 730 Java API requirements: 54 classes, 3 interfaces, 94
fields, 126 constructors, and 453 methods. The inventory contains 610 public
and 120 protected symbols, including the compiler-generated bridge required by
binary consumers. Symbol presence does not establish JInterface behavior or
wire interoperability, which require differential suites.

## Evidence

`test:gotp.compat.otp-java-api-laws` proves source/class digests, compiler pin,
exact kind and visibility partitions, strict ordering, complete ledger
coverage, descriptor preservation, malformed-class totality, and stale-input
rejection.
