# Email CSS image references

This Rust helper uses Servo's `cssparser` tokens and source positions to identify image references.
It returns `[start_byte, end_byte, decoded_url, nested_image]` arrays in source order.
Elixir makes tracker/proxy decisions and splices replacements into the original CSS.
The helper does not format CSS or fetch URLs.

Inline styles are parsed as declaration lists. Returned offsets address
the original UTF-8 input, including any BOM. Image-set candidate strings are images;
strings inside `type()` and non-image declarations such as font `src` are not.

CSS parsing runs in a disposable Rust helper managed by an
Erlang port in a monitored process that traps port exits. Elixir decodes and validates
its bounded JSON reply with Jason. This
isolates native stack overflows and aborts from the delivery VM. Email content passes
through private stdin, not command arguments; helper diagnostics are not logged.

Each input is limited to 1 MiB. Each helper has a 256 MiB address-space limit, a
two-second CPU limit, a three-second wall-clock termination alarm, no core dumps,
a three-second reply deadline, and a 4 MiB output limit. Nesting is capped at 128.
The caller independently bounds its wait at 3.2 seconds. The helper catches ordinary
Rust panics. Bad tokens, incomplete strings/comments/URLs/blocks, invalid spans,
helper crashes, timeouts, or an unavailable helper cause the email pipeline to
retain the original content, omit branding
footers, and skip independent image visits. These limits can reject valid CSS.

Tracker removal, original image discovery, and optional branding share a two-second
per-email budget in an unlinked supervised task. At most 20 privacy tasks run at once.
The image jobs consume the prepared original URL list; no CSS is parsed after delivery.

`mix compile` builds and packages the executable in `priv/bin`. The helper
requires Unix resource limits; unsupported platforms fail open.

Rust 1.94.0 is pinned in the application's mise toolchain, Docker build, and CI.
`cssparser` is pinned in Cargo.toml and Cargo.lock. Changes to these
versions require running the email tests, especially source preservation and fail-open
delivery cases. Build and lint from the application directory:

```sh
mix compile
cargo fmt --manifest-path tools/css_image_parser/Cargo.toml --check
cargo clippy --manifest-path tools/css_image_parser/Cargo.toml --locked -- -D warnings
```
