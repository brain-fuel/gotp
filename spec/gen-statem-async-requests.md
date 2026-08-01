# Pinned gen_statem asynchronous requests

- Specification: `spec:gotp.otp.gen-statem-async-requests`
- Parent: `spec:gotp.otp-29-0-4-compatibility`
- Decision: `adr:gotp.pinned-gen-statem-async-requests`
- Deployable code: `code:gotp.erts.otp29-gen-statem-async`

GoTP executes all fourteen OTP 29.0.4 `gen_statem` asynchronous request
exports from the unmodified pinned BEAM. Evidence covers direct and labeled
collection requests, all wait/receive arities, response checking, request-ID
creation/addition/size/list conversion, deletion and retention, timeout retry
and abandonment, late-response suppression, live crashes, dead servers, local
names, out-of-order replies, and mailbox cleanliness.

The stateful law creates up to eight live requests, releases them in generated
permutations, and requires both callback modes to preserve response labels and
decrement collection cardinality after every deletion. Distributed server
references and exhaustive invalid-input domains remain outside this partial
compatibility claim.
