# Edge script: geo-localized pricing

Bunny middleware rewrites elements with `data-price-world` using `HTMLRewriter`.
The static website contains UK prices. Visitors in GB, GG, JE, and IM keep those
prices; other country codes receive the worldwide values from the HTML attributes.

| Visitor | Price |
| --- | --- |
| UK and Crown dependencies | £25/year |
| Worldwide | $35/year |

## Middleware behavior

- `onOriginRequest` removes Range and If-Range for GET/HEAD URLs ending in `/`
  or `.html`. Bunny injects origin ranges even for full client requests; fetching
  full HTML prevents stale byte lengths after rewriting. Asset ranges,
  URLs, queries, authentication, and other methods remain unchanged.
- `onOriginResponse` rewrites HTML prices and sets `Cache-Control: no-store`
  for both UK and worldwide responses. Worldwide HTML is buffered to measure
  the exact UTF-8 byte length: replacing £ with $ shortens each price by one byte.
  UK HTML and non-HTML assets retain their streamed bodies. HEAD and null-body
  responses stay bodyless.
- `onClientResponse` repairs native empty 400 responses for missing directory
  URLs. For GET/HEAD only, it probes the same-origin explicit `index.html` without
  ranges or redirects. Only an actual 404 replaces the original response, using
  the site's custom error page with `no-store`. The 10-second timeout includes
  reading the error body. Other statuses, asset errors, and probe failures keep
  their original response.

The client-response hook requires **Pull Zone → General → Origin → Run script
before cache**. Enable it separately for staging and production. It executes the
script for cached requests too, increasing execution volume. Workflows do not
change this setting.

Regression tests cover response framing, immutable headers, range removal,
bodyless responses, and failure handling. Verify that missing-directory responses
match the explicit-index custom error page, including GET and HEAD requests.

## Local development

Run from `website/edge-script`:

```sh
deno task test
deno task check
deno task build
```

`deno task build` bundles the SDK and middleware into ignored `dist/index.ts`.
`deno task dev` proxies `https://shroud.email/` locally. The configured origin URL
is local-only; native Bunny execution uses the attached Pull Zone's origin.

## Deployment

The root workflows deploy the website first, then its middleware:

| Environment | Workflow | Script ID secret | Deploy key secret |
| --- | --- | --- | --- |
| Staging | `.github/workflows/website-deploy-staging.yml` | `WEBSITE_BUNNY_STAGING_SCRIPT_ID` | `WEBSITE_BUNNY_STAGING_DEPLOY_KEY` |
| Production | `.github/workflows/website-deploy.yml` | `WEBSITE_BUNNY_SCRIPT_ID` | `WEBSITE_BUNNY_DEPLOY_KEY` |

Each secret pair must identify a Middleware script attached to the corresponding
Pull Zone. Existing working scripts can be reused; no new script or zone is
required. Website deployment also requires `BUNNY_API_KEY`.

Every deployment replaces the script after the site job succeeds. Production
deploys on relevant `main` pushes; staging remains manual. Manual deployments
use GitHub's branch/tag selector and publish the same commit for both jobs.
See [website deployment instructions](../README.md#official-bunny-website-deployments)
for the required pricing cache rule and deployment safeguards.

The site job checks `no-store` with HEAD; the edge-script job follows publication
with a complete pricing GET. Also check
missing-directory GET/HEAD, home, docs, and assets. Verify £25/year from a UK
network and $35/year from a non-UK network, using fresh browser caches. A supplied
country header alone does not prove geographic isolation.

## Changing prices

Update the UK defaults and `data-price-world` values in
`website/src/components/organisms/Pricing.vue`. Update `UK_COUNTRY_CODES` in
`src/pricing.ts` only when the billing-country grouping changes.
