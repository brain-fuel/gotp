# Pinned gen_server remaining-runtime callback fixture

`gen_server_remaining_callbacks.beam` is compiled from the adjacent Erlang
source with the compiler in the official `erlang:29.0.4-alpine` image. The
oracle runs each case in an isolated monitored process and emits deterministic
base64-encoded external terms.

The fixture directly executes `init_it/6` through valid `proc_lib` children and
covers acknowledgements, success, ignore/error/stop, bad returns/actions,
callback crashes, registration cleanup, and parent metadata. Delayed
hibernation cases cover calls, casts, info, timeout, system control, malformed
post-wake callbacks, linked-parent exits, and termination. It also covers
`abcast/2,3`, `stop/3`, and the remaining `system_*` exports.

- `gen_server_remaining_callbacks.erl`: `47e6e9cd9708a3a691a440c5b851ba469676acc91133ad0eaa1a6b82d83981be`
- `gen_server_remaining_callbacks.beam`: `4a355e908ddac83af34374e85405267794953ba7949f019593286621c74cef92`
- remaining-runtime corpus: `16b631a54b57d2be065df148b82684e037326d81dd6021558588dbe84f18944f`
