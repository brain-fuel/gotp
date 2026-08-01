# Pinned gen_statem static-type oracle

`gen_statem_type_fixture.erl` is compiled with `+deterministic` using the
official `erlang:29.0.4-alpine` image. Each case asks the unmodified
`gen_statem.beam` lifecycle engine to accept or reject a callback result,
action, event type, start option, or server name. Results and source terms are
stored as deterministic base64-encoded ETF.

- fixture source: `1ac5188c369ccaa7ee67af1aa9b5b5860c6ef2870679f3b9ea4f1716795e6b21`
- fixture BEAM: `e881cb5906ba64e8bbd209aaa08bbc6ce8f9021d27063468b2873e6fb951c246`
- acceptance corpus: `6d52c03edcf7873b56845d3b68fb8315b389abe35aad7cece1c84787dfb13da5`
