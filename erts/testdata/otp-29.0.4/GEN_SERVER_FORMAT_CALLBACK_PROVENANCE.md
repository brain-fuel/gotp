# Pinned gen_server formatting callback fixtures

The adjacent callback modules are compiled with the compiler in the official
`erlang:29.0.4-alpine` image. The oracle runs every case in an isolated
monitored process and emits deterministic base64-encoded external terms.

The modern fixture covers byte-exact legacy, multi-line, single-line,
depth-limited, character-limited, Unicode, termination, crash, and
no-handle-info rendering. Live status cases cover normal and suspended servers,
malformed status data, modern callback formatting, and ordinary-versus-entered
status equivalence. The second fixture exercises deprecated callback
`format_status/2` independently.

- `gen_server_format_callbacks.erl`: `8a46d001a724c272416e008fa55370e52213744b7a908251a30a12aa4a01bed1`
- `gen_server_format_callbacks.beam`: `229a4fcbb7f0ba1fa63f4c298c1a3cb1ba1227d48aefdab1789375fa324a243e`
- `gen_server_format_legacy_callbacks.erl`: `29f1e1ddd600a562e665c30fc499fa715dfec145cd76f2fb042503aef8961d09`
- `gen_server_format_legacy_callbacks.beam`: `76a4a2a82aa6dbfbd2cdb764ed81fe0be08237ef7332b8ac5e4b290303535d85`
- formatting corpus: `1cac7d64079874e13b969ad3809a572986b15f052e09b08bffc254b3898e541a`
