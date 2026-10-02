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
The native runtime's wire framing remains unresolved; unit tests validate the
returned Response, not Bunny's serialization of it.

For `/pricing`, `/pricing/`, and `/pricing/index.html`, temporary `shroud-pricing`
logs record the origin framing, entry into body buffering, and the actual byte
count and headers just before returning. They exclude URLs, query strings,
cookies, credentials, and response contents. Worldwide rewritten pricing also
returns `X-Shroud-Pricing-Revision: framing-diagnostics-v1`. The workflow prints
only framing/cache/revision headers and the received byte count, preserving
curl's failure status. Compare those headers with Bunny's script logs: if
`before-buffer` appears without `return-response` for the same invocation,
execution did not complete. UK and HEAD/bodyless responses skip both events.
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
