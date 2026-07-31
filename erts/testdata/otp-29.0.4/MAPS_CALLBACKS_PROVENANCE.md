# Pinned maps callback fixture

`maps_callbacks.beam` is compiled from `maps_callbacks.erl` with the compiler in
the official `erlang:29.0.4-alpine` image. It exists only to supply ordinary
BEAM closures to the unmodified OTP `maps.beam` differential corpus.

Regenerate from the repository root with:

```sh
podman run --rm -v "$PWD:/workspace" -w /workspace erlang:29.0.4-alpine \
  erlc -o erts/testdata/otp-29.0.4 erts/testdata/otp-29.0.4/maps_callbacks.erl
```
