# Pinned gen_server asynchronous-request callback fixture

`gen_server_async_callbacks.beam` is compiled from the adjacent Erlang source
with the compiler in the official `erlang:29.0.4-alpine` image. Every oracle
case runs in an isolated process. The fixture covers direct and collection
requests, success, retryable timeout, abandonment and late-reply suppression,
exact server-crash errors, local names, out-of-order replies, and explicit
message checking.

- `gen_server_async_callbacks.erl`: `cab73a657a95ed8dec15bf2db46467346c137ee8c52340565deaa0874a2810ae`
- `gen_server_async_callbacks.beam`: `24d5c8c2676b17331481e07f1334dd35de17131680e3dc3de69913f1fcb491db`
- asynchronous corpus: `62014e459c5f61dd37c65dbd92d8db0d5a62f5a91e08d01f1cb4da19b81b6e38`
