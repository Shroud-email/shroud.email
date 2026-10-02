# Edge script: geo-localized pricing

A bunny.net **middleware** edge script that rewrites the displayed price on the
pricing page based on the visitor's country, using bunny's `CDN-RequestCountryCode`
header and `HTMLRewriter`. Rewritten HTML is buffered to publish its exact byte length.

| Visitor         | Price shown   |
| --------------- | ------------- |
| UK (GB, GG, JE, IM) | £25/year  |
| Everywhere else | $35/year      |

## How it works

The static site (`/pricing/`) ships with the **UK price as the default**
(`£25/year`). The price is marked in HTML with
`data-price=""` attributes (on the hero heading and the price table cell), and
the Pricing Vue component is rendered with **no `client:load`** — so the price
is plain static HTML with no hydration that could snap it back.

On every request, bunny injects `CDN-RequestCountryCode` (ISO-3166-1 alpha-2).
The middleware:

1. Reads the country on `onOriginResponse`.
2. For **non-UK** visitors, runs the response through `HTMLRewriter`, replacing
   the inner content of every `[data-price]` element with `$35/year`.
3. For **UK** visitors (or when the header is missing), passes the response
   through unchanged — they already see £25/year in the static HTML.
4. Sets `Cache-Control: no-store` on HTML responses in **both** cases so the
   rewritten (or default) HTML is never cached and served to a visitor in the
   other region. (Static assets keep their original cache headers.)

This means the script degrades safely: if the script is disabled or the header
is absent, visitors see the UK default.

### Response framing

UK price strings contain `£` (two UTF-8 bytes), while `$` occupies one byte, so
the three pricing spans shorten the body by three bytes. Preserving the origin's
length makes clients wait for bytes that will never arrive. The deletion-only
fix and the explicit byte-length override were both published, but staging still
advertised the origin length, including after a pull-zone cache purge. The user
confirmed that the deployed source contains the explicit override.
The worldwide handler therefore buffers the transformed HTML and explicitly
sets `Content-Length` to the output buffer's byte length, not its character count.
It uses a mutable copy of the context response so immutable Fetch headers are
not modified. UK responses and assets retain their unchanged, streamed bodies.
Live diagnostics showed directory URLs arriving at the origin-response hook as
206, while an explicit `index.html` arrived as 200. The handler completed and
returned the correct byte length in both cases. The two rewritten bodies were
byte-for-byte identical, but only the directory response retained the stale
length on the wire. The native internals behind that difference are not public.

The attempted explicit-index origin rewrite did not fix it: native logs showed
the URL was resolved but the origin request still contained Range and returned
206, even though the client GET did not request a range. This points to the
partial-response path rather than directory resolution alone.

The origin-request hook now removes Range and If-Range for GET/HEAD paths ending
in `/` or `.html`, so HTML can be fetched in full before changing byte offsets.
It leaves URLs, queries, authentication and other headers intact. Asset ranges,
extensionless paths without trailing slashes, and other methods are unchanged.
The unsuccessful URL rewrite was removed. Staging must still verify that Bunny
honors the cleared origin range headers and returns full responses.

Temporary `shroud-pricing` logs now cover every origin response without a path
filter. Sites configures an origin prefix `/deploys/<release>/`; the native
middleware logs confirmed deploy-prefixed paths, so a public-path-only diagnostic
filter excluded those rewritten requests. The initial v1 diagnostics used that
filter and produced no logs in the user's capture.

Revision `html-ranges-v4` logs script startup and middleware registration,
including whether the native Bunny global exists. Per-request logs include
method, status, validated country, path-shape flags (not actual URLs), framing,
content type, cache control, stream state, transformation/buffering checkpoints,
replacement count, and returned headers. Every branch logs its outcome;
buffering errors log their type and are rethrown. Logs exclude URLs, query
strings, cookies, credentials, error messages, and response contents. All HTML
responses return `X-Shroud-Pricing-Revision: html-ranges-v4`. The origin-request
log records HTML classification, bounded numeric byte-range values and incoming
and outgoing Range/If-Range presence. The workflow prints
only framing/cache/revision headers and the received byte count, preserving
curl's failure status. Compare those headers with Bunny's script logs: if
`before-buffer` appears without `return-response` or `buffer-error` for the same
invocation, buffering has not completed. UK, HEAD/bodyless, and non-HTML
responses have distinct pass-through/return events instead.
A correct logged length but incorrect wire length points to subsequent response
handling. Remove these temporary diagnostics once the native framing issue is resolved.

## Files

- `src/main.ts` — entry point (imports `pricing.ts`).
- `src/pricing.ts` — the middleware.
- `src/bunny-globals.d.ts` — ambient types for bunny runtime globals
  (`HTMLRewriter`) not shipped with the SDK.
- `build.mjs` — esbuild + `@luca/esbuild-deno-loader` bundler, inlines the
  `https://esm.sh/...` SDK import into a single `dist/index.ts`.
- `deno.json` — Deno tasks (`build`, `check`, `dev`).

## Local development

```bash
cd edge-script

# Type-check
deno check src/main.ts

# Test response framing and price replacement without network access
deno task test

# Bundle to dist/index.ts
deno task build

# Run locally (proxies to https://shroud.email/ as the origin)
deno task dev
```

Then test with curl (simulating a non-UK visitor — the default origin HTML
already has £25, so the script rewrites to $35):

```bash
curl http://127.0.0.1:8080/pricing/ | grep data-price
```

## Deploy (staging)

Deployment is via a **manual** GitHub workflow:
`.github/workflows/deploy-edge-script.yml` (run it from the Actions tab).

### One-time setup in bunny

1. In the bunny dashboard, create an **Edge Script** of type **Middleware**.
2. Attach it to your **staging Pull Zone** (the one fronting the static site).
3. Under **Script → Deployments → Settings**, copy the **Script ID** and
   **Deploy Key**.

### One-time setup in GitHub

Add two repository secrets (Settings → Secrets and variables → Actions):

| Secret name                  | Value                          |
| ---------------------------- | ------------------------------ |
| `BUNNY_STAGING_SCRIPT_ID`    | The edge script id             |
| `BUNNY_STAGING_DEPLOY_KEY`   | The script's deploy key        |

### Deploy

Run the **"Deploy edge script (staging)"** workflow from the Actions tab. It
type-checks, bundles, and uploads `edge-script/dist/index.ts` to bunny.

### Verify

With the script attached to the staging pull zone, check the rewritten price:

```bash
# Non-UK (e.g. US) — bunny routes through a non-UK PoP, expect $35/year
curl -s https://staging.shroud.email/pricing/ | grep -o 'data-price="">[^<]*'

# Force a UK egress isn't trivial from curl; verify from a UK network/VPN,
# or check the bunny dashboard → Script → Logs.
```

## Production

Once validated on staging:

1. Create a production Edge Script + attach to the production Pull Zone.
2. Add `BUNNY_SCRIPT_ID` / `BUNNY_DEPLOY_KEY` secrets and copy this workflow
   to `deploy-edge-script-prod.yml` (or extend the existing one with an
   environment selector).

## Changing the prices

Edit `WORLDWIDE_PRICE` and `UK_COUNTRY_CODES` in `src/pricing.ts`, **and** the
default price baked into `src/components/organisms/Pricing.vue` (the UK price
must stay the static default so the no-script fallback stays correct).
