# Pinned gen_statem formatting callback fixtures

The adjacent callback modules are compiled with `+deterministic` using the
compiler in the official `erlang:29.0.4-alpine` image. The oracle executes each
case in that image and emits deterministic base64-encoded external terms.

The shared fixture defines termination reports, status normalization, and
public formatter inputs. Modern and deprecated callback fixtures independently
exercise `state_functions` and `handle_event_function`. The two corpora cover
11 cases each; the Go+ property test supplies generated state, data, event, and
option terms beyond those fixed examples.

- `gen_statem_format_fixture.erl`: `2c54cb9efdb6ddb6a9225e9b5673508daf63642ad6fd5e86dfb1900de3a1d1ca`
- `gen_statem_format_fixture.beam`: `dde480dba654b2c873ea0d012046bc7cf16cb8e54c21ccab58ec34cfee2d187b`
- `gen_statem_format_state_functions_callbacks.erl`: `3e23e1e3d48c0c43cf09c5dde1be70b0202478bcda069e0082563c2a75133b44`
- `gen_statem_format_state_functions_callbacks.beam`: `db65cf824ee68de78fe3533aa4b0b4729bc073e2ab4a6c9c6dcd949b8a8dc238`
- `gen_statem_format_handle_event_callbacks.erl`: `8a19996aca46908b10f59a2ed95a921436a41afd5f664d8e24c9f383bbc489cb`
- `gen_statem_format_handle_event_callbacks.beam`: `5ab200d63a8a6b0be942922376a95d6a743832a32fa96529c0175f03ce7dae91`
- `gen_statem_format_state_functions_legacy_callbacks.erl`: `61754a0d086a22df7adbb0ef76744cb186f9a69fbb65fee64ce18f9ecacd2d44`
- `gen_statem_format_state_functions_legacy_callbacks.beam`: `07c1258cf1cf01222021223cf0148ecb2e304f335050d8f4b405995ae52eb6f2`
- `gen_statem_format_handle_event_legacy_callbacks.erl`: `400f05a52dc77deb9654865d3c86fbcdb6806762386b00cdab0d79bab2846a26`
- `gen_statem_format_handle_event_legacy_callbacks.beam`: `bc4c1102e6ffb072a8a023a49a73d31809f5e6c7be838e891bc69589b2625177`
- state-functions corpus: `18f220a05226322b880b9eeee2f5c486722acf38f147a048c7843cb24f8ffa92`
- handle-event corpus: `6d4b839bd810f208b4de4e88f67adb736d39715eee11e55900d14ae82cbd09b6`
