# Pinned gen_server callback fixture

`gen_server_callbacks.beam` is compiled from the adjacent Erlang source with
the compiler in the official `erlang:29.0.4-alpine` image. It drives the
unmodified pinned `gen_server.beam` through start, call, cast, explicit reply,
system stop, callback termination, monitored normal exit, linked and monitored
starts, timeout alias suppression, exact callback-crash propagation,
continuation and info callbacks, parent-link failure, named duplicate starts,
and suspended system code change.

- `gen_server_callbacks.erl`: `7fa0aa41f904c2c16065de94dbcbc540248aab55ae10291c493d278f0a3b6416`
- `gen_server_callbacks.beam`: `ad5045f2062900129aa7eb74cf3d9cb82c0cb79cac7af0d6f13348d5b6dc7956`
- lifecycle corpus: `107c3a6a92d360f45746c41b547fe0d131b497d595e09b4397630fcab180b641`
- `logger_config.beam`: `5ab4b78512175d37fa87fc7bffd0e647b467cfab02bab0b8c96d4971da1569a8`
