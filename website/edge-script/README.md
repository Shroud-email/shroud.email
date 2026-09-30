# Edge script: geo-localized pricing

A bunny.net **middleware** edge script that rewrites the displayed price on the
pricing page based on the visitor's country, using bunny's `CDN-RequestCountryCode`
header and `HTMLRewriter` (streaming, no buffering).

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
   the inner content of every `[data-price-world]` element with that element's
   `data-price-world` value (such as `$0` or `$35/year`).
3. For **UK** visitors (or when the header is missing), passes the response
   through unchanged — they already see £25/year in the static HTML.
4. Sets `Cache-Control: no-store` on HTML responses in **both** cases so the
   rewritten (or default) HTML is never cached and served to a visitor in the
   other region. (Static assets keep their original cache headers.)

This means the script degrades safely: if the script is disabled or the header
is absent, visitors see the UK default.

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

Deployment is part of the **Website staging deployment** workflow:
`.github/workflows/website-deploy-staging.yml`. Run it manually from the
Actions tab on `main`; it deploys both the site and edge script from `main`.

### One-time setup in bunny

1. In the bunny dashboard, create an **Edge Script** of type **Middleware**.
2. Attach it to your **staging Pull Zone** (the one fronting the static site).
3. Under **Script → Deployments → Settings**, copy the **Script ID** and
   **Deploy Key**.

### One-time setup in GitHub

Add two repository secrets (Settings → Secrets and variables → Actions):

| Secret name                             | Value                   |
| --------------------------------------- | ----------------------- |
| `WEBSITE_BUNNY_STAGING_SCRIPT_ID`       | The edge script id      |
| `WEBSITE_BUNNY_STAGING_DEPLOY_KEY`      | The script's deploy key |

### Deploy

Run **Website staging deployment** from the Actions tab. Its edge-script job
type-checks, bundles, and uploads `website/edge-script/dist/index.ts` to bunny.

### Verify

With the script attached to the staging pull zone, check the rewritten price:

```bash
# Non-UK (e.g. US) — bunny routes through a non-UK PoP, expect $35/year
curl -s https://staging.shroud.email/pricing/ | grep -o 'data-price[^>]*>[^<]*'

# Force a UK egress isn't trivial from curl; verify from a UK network/VPN,
# or check the bunny dashboard → Script → Logs.
```

## Production

Production deployment is handled by `.github/workflows/website-deploy.yml`.
The **Website production deployment** workflow runs for website changes pushed
to `main` and can also be started manually. It deploys both the site and edge
script.

For the production edge script, create and attach a production Edge Script to
the production Pull Zone, then configure the `WEBSITE_BUNNY_SCRIPT_ID` and
`WEBSITE_BUNNY_DEPLOY_KEY` repository secrets.

## Changing the prices

Edit the `data-price-world` values and static UK prices in
`src/components/organisms/Pricing.vue`, and edit `UK_COUNTRY_CODES` in
`edge-script/src/pricing-country.ts`. The UK price must stay the static default
so the no-script fallback stays correct.
