# Pinned gen_server multi-call callback fixture

`gen_server_multicall_callbacks.beam` is compiled from the adjacent Erlang
source with the compiler in the official `erlang:29.0.4-alpine` image. The
oracle harness starts two real OTP peer nodes plus its local node and isolates
every case. Node identities are normalized to stable semantic roles before ETF
encoding so container hostnames do not affect the corpus.

The fixture covers all three exports, healthy local and remote servers, missing
registration, unavailable nodes, callback crashes, timeout and late-response
cleanup, duplicate and empty node lists, and reply/bad-node ordering.

- `gen_server_multicall_callbacks.erl`: `a4e057457200d797852f381050f3fc629745c87bb879a07e597ff0c34260b95e`
- `gen_server_multicall_callbacks.beam`: `e0a16ac918c1667dc70c6d41772b95cd3b69742dfa10e3cb608fc36d8f1e071b`
- multi-call corpus: `408298f0caee48d5f449e757017a5902eff380fe0509e31e9f1ac3466d56a444`
