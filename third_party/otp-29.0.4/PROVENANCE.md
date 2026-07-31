# Erlang/OTP 29.0.4 provenance

- Upstream: https://github.com/erlang/otp
- Tag: `OTP-29.0.4`
- Tag object: `a1f686ce28059bee32fa1216e5fa3fa629e70814`
- Peeled commit: `1259612946cb36a8bf9614b289090bb32fbcbeb2`
- License: Apache-2.0

Vendored files:

| Local path | Upstream path | SHA-256 | Purpose |
|---|---|---|---|
| `LICENSE.txt` | `LICENSE.txt` | `809fa1ed21450f59827d1e9aec720bbc4b687434fa22283c6cb5dd82a47ab9c0` | Upstream license |
| `lib/compiler/src/genop.tab` | `lib/compiler/src/genop.tab` | `79cf0ee1df79f0b50f5055338cbf4ee238115c12db862de89f7fca0c5309b017` | Stable generic BEAM opcode numbers, names, and arities |

`genop.tab` is input data for `internal/opcodegen`; generated Go code records
its source version and digest. No Erlang/OTP implementation code is linked into
the MIT-licensed GoTP core.
