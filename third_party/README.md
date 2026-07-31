# Third-party provenance

No Erlang/OTP source is vendored in the initial GoTP core.

Compatibility data is derived from the public `OTP-29.0.4` release and is
recorded in `baseline/otp-29.0.4.yaml`. Future copied fixtures, headers, opcode
tables, or applications must receive a subdirectory containing:

- upstream repository and immutable commit;
- original path;
- SPDX identifier;
- unmodified license text;
- generation or modification notes.
