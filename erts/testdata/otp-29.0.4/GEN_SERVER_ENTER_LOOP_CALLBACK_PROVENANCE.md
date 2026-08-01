# Pinned gen_server enter-loop callback fixture

`gen_server_enter_loop_callbacks.beam` is compiled from the adjacent Erlang
source with the compiler in the official `erlang:29.0.4-alpine` image. The
oracle harness runs every scenario in an isolated monitored process and emits
one deterministic base64-encoded term per case.

The fixture covers `enter_loop/3,4,5`, valid `proc_lib` ancestry, anonymous and
local/global/via names, timeout/hibernate/continue actions, ordinary and system
messages, code change, termination, linked-parent failure, and exact invalid
caller, registration, and action reasons.

- `gen_server_enter_loop_callbacks.erl`: `76907a503ff7f8a7bd4292967e4a69fa26a40f7feadc9baef2be4aac75106368`
- `gen_server_enter_loop_callbacks.beam`: `6db9488e9a0f8db83cf53a835053839ec9e69afee0efe7e3c782506b7662888b`
- enter-loop corpus: `45910f50f9f1279f8a207ff4b3f81c2e4a9e8ee4e7c5163f02a5d3c83011d151`
