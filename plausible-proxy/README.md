# Plausible proxy on Bunny.net

A standalone Bunny Edge Script that proxies Plausible's personalized JavaScript
and event API. Adapted from the
[Plausible Cloudflare guide](https://plausible.io/docs/proxy/guides/cloudflare),
using Bunny's HTTP SDK and CDN caching instead of Cloudflare Workers APIs.

## Configure and deploy

1. In Plausible, open your site's **Settings → General → Site Installation**.
   Copy the personalized `https://plausible.io/js/pa-XXXXX.js` URL into
   `PROXY_SCRIPT` in `src/proxy.ts`.
2. Optionally change `SCRIPT_PATH` and `EVENT_PATH`. The defaults are
   `/qwerty/script.js` and `/qwerty/event`. Avoid names containing `plausible`,
   `analytics`, `tracking`, or `stats`, which are more likely to be blocked.
3. From this directory, install the local toolchain and build:

   ```sh
   mise install
   mise exec -- deno task check
   mise exec -- deno task test
   mise exec -- deno task build
   ```

4. In Bunny's dashboard, create an **Edge Script → Standalone** script (not
   middleware). Under **Deployments → Settings**, copy the script ID and deploy
   key. Use the script's connected Pull Zone and add the custom hostname
   `p.shroud.email`, configure its DNS, and enable SSL.
5. On that Pull Zone, set **Caching → Cache expiration time** to **Respect
   origin Cache-Control**. Successful script responses cache for one hour;
   events and all errors use `no-store`. Also disable **Cache Error Responses**
   to avoid relying on its precedence over `no-store`. Do not add rules that
   force caching of the event route or errors. Purge the script URL after
   changing the upstream personalized script URL.
6. Add the GitHub repository secrets listed below before merging. Commit the
   configured proxy and workflow, then merge to `main` to deploy automatically.
   To deploy manually, run **Plausible proxy CI and deployment** from GitHub's
   Actions tab. Use **Use workflow from** to select the branch or tag to deploy.

### GitHub Actions deployment

The root `.github/workflows/plausible-proxy.yml` workflow checks formatting,
lints, type-checks, tests, and bundles the proxy on relevant pull requests and
pushes to `main`. Changes under `plausible-proxy/` or to the workflow deploy
automatically on `main` after those checks pass. Pull requests only validate;
they do not deploy. Manual deployment (`workflow_dispatch`) is also available.
Publication uses the official, SHA-pinned `BunnyWay/actions/deploy-script`
action to upload `plausible-proxy/dist/index.ts`. The workflow refuses to
publish the placeholder personalized script URL. Automatic and manual
deployments share a concurrency group so they cannot replace the same script
concurrently.

Required GitHub repository secrets:

| Secret                       | Value                            |
| ---------------------------- | -------------------------------- |
| `PLAUSIBLE_BUNNY_SCRIPT_ID`  | The standalone Bunny script's ID |
| `PLAUSIBLE_BUNNY_DEPLOY_KEY` | That script's deploy key         |

This workflow uses script-scoped credentials, not the account-wide Bunny API
key. It publishes code only; it does not configure DNS, SSL, or Pull Zone cache
settings. Complete those settings before running it and perform the live checks
below after publication.

For a dashboard-only deployment, paste `dist/index.ts` into the Bunny editor and
deploy it instead of running the workflow.

This is a dedicated proxy: all other paths return 404. Do not replace your
website's origin with it. Browsers must connect directly to Bunny for this
implementation to preserve visitor IPs. Putting another reverse proxy in front
of Bunny makes Bunny's `X-Real-IP` identify that proxy, not the visitor; Bunny
replaces incoming `X-Real-IP` and `X-Forwarded-For`. An extra-hop, same-host
subdirectory setup therefore needs a separate authenticated forwarding design
and is not supported by this script. Do not accept arbitrary client-supplied IP
headers as a workaround.

## Install the snippet

Keep the initialization snippet from Plausible's site settings, changing both
the script URL **and** the event endpoint:

```html
<script async src="https://p.shroud.email/qwerty/script.js"></script>
<script>
window.plausible = window.plausible || function () {
  (plausible.q = plausible.q || []).push(arguments);
};
plausible.init = plausible.init || function (i) {
  plausible.o = i || {};
};
plausible.init({ endpoint: "https://p.shroud.email/qwerty/event" });
</script>
```

Update the snippet's URLs if you change the configured paths. Update your
Content Security Policy's `script-src` and `connect-src` if required. The event
proxy passes through Plausible's CORS response headers and forwards OPTIONS
requests for cross-origin preflights.

## Behavior and verification

- JavaScript supports GET/HEAD; events support POST/OPTIONS. Other methods
  return 405. Paths match exactly, not arbitrary suffixes or caller-selected
  upstreams.
- Event bodies, user agents, referrers, and origins pass through unchanged.
  Cookies, authorization, and unrelated request headers are never forwarded.
- Bunny's `X-Real-IP` becomes Plausible's `X-Forwarded-For` for visitor counting
  and geolocation. Incoming `X-Forwarded-For` is not trusted. Run this behind
  Bunny CDN; locally, IP headers must be simulated and are not trustworthy.
- Upstream status/body/CORS headers are preserved; network failures return 502.
  No event payloads or visitor IPs are logged by this script.

After deployment, open the script URL and confirm it contains JavaScript. Visit
your site, check that browser requests go to the new event URL (not
`plausible.io`), and confirm the visit appears in Plausible's realtime
dashboard. Also verify visitor geolocation from a known location after
deployment. Request an unknown path repeatedly and confirm the 404 response has
`Cache-Control: no-store` and is not served from Bunny's cache. Confirm event
responses are also uncached; local tests cannot verify CDN cache policy.

For local development, run `mise exec -- deno task dev`; the SDK listens on port
8080. Tests mock the upstream and do not send analytics events to Plausible.
