# `lists_callbacks.beam` test fixture

- Compiler: official `erlang:29.0.4-alpine` image.
- ERTS: `17.0.4`.
- Source: `lists_callbacks.erl` in this directory.
- Purpose: construct BEAM local funs that exercise higher-order exports of the
  unmodified OTP `lists.beam` fixture through GoTP module linking.
