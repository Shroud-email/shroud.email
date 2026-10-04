# Edge script: geo-localized pricing and text analytics

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
- A second `onClientResponse` hook sends `$pageview` events to the
  website's PostHog project for successful GET requests to `/llms.txt`,
  `/llms-full.txt`, and paths ending in `.md`. It includes partial responses and
  304 revalidations, but excludes HEAD requests, redirects, and errors. File
  contents, headers, and caching remain unchanged.

## Text analytics

In PostHog, count `$pageview` events filtered by `capture_source = edge`. Break
down by `$pathname`, `format`, `$host`, `$raw_user_agent`, or `country`. The host
distinguishes staging from production. `$current_url` contains the origin and
path without query strings. User-agent strings can suggest a crawler, but do not
prove AI usage. These are request counts, not unique visitors or confirmed reads.
Browser cache reads that never reach Bunny cannot generate events.

Text-file requests share the browser pageview event name, so unfiltered pageview
counts include both. The edge does not generate browser dimensions or session
IDs; these events do not represent browser sessions. PostHog also supports
[`$http_log`](https://posthog.com/docs/web-analytics/sending-http-logs) for dedicated
server request analytics. `$raw_user_agent` supports PostHog's
[bot classification functions](https://posthog.com/docs/web-analytics/bot-detection).

Each request uses a random distinct ID with person profiles and GeoIP lookup
disabled. The payload excludes client IP addresses, cookies, referrers, and query
strings. Country comes from Bunny's country header; user-agent is limited to 512
characters. No browser tracking code is added to the text files.

Tracking uses the `posthog-node/edge` entry point, pinned to version 5.55.0 with
dependencies recorded in `deno.lock`. Each tracked request creates a client and
awaits `captureImmediate`, sending a single-event batch without background
flushing, compression, feature flag polling, or retries. The SDK adds
`$lib = posthog-edge`, `$lib_version`, and `$is_server = true`.

The Bunny SDK exposes no background-task lifetime hook. Analytics sends use a
one-second request timeout, so tracked file requests can incur approximately one
second of extra latency when PostHog is unavailable. Network errors and rejected
sends do not change file delivery; events are best-effort and are not retried.

The client-response hook requires **Pull Zone → General → Origin → Run script
before cache**. Enable it separately for staging and production. It executes the
script for cached requests too, increasing execution volume. Workflows do not
change this setting.

Regression tests cover response framing, immutable headers, range removal,
bodyless responses, analytics metadata, and failure handling. Verify that
missing-directory responses match the explicit-index custom error page, including
GET and HEAD requests.

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
Local tests and development allow reading only `POSTHOG_CAPTURE_MODE` from the
environment because the PostHog SDK checks it during client construction.

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
