# Pinned gen_server callback fixture

`gen_server_callbacks.beam` is compiled from the adjacent Erlang source with
the compiler in the official `erlang:29.0.4-alpine` image. It drives the
unmodified pinned `gen_server.beam` through start, call, cast, explicit reply,
system stop, callback termination, and monitored normal exit.

- `gen_server_callbacks.erl`: `e8239f7fe955f0e30376dde6179b54f653bee61ab5ec43b10688df69166f2e11`
- `gen_server_callbacks.beam`: `7e7ca0b5b92b17b872470ab53e8e047e1249dfa805d48c10b7bda0361bdf2ea5`
- lifecycle corpus: `b1087a0833bea440f030f97a3732e81aed9c6aec32a3a0d33db8343971d137a0`
