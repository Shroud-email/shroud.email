# Shroud.email

This is the website running on [Shroud.email](https://shroud.email). It's a fast, static site built with [Astro](https://astro.build).

## Commands

Run commands from `website/`, using its mise toolchain (`mise exec -- <command>`):

| Command           | Action                                       |
|:----------------  |:-------------------------------------------- |
| `pnpm install --frozen-lockfile` | Installs dependencies from the lockfile |
| `pnpm run dev`     | Starts the local dev server                 |
| `pnpm run build`   | Build your production site to `./dist/`      |
| `pnpm run preview` | Preview your build locally, before deploying |

## Documentation

Starlight powers `/docs/` within this Astro site; marketing and blog pages keep
their existing layouts. Guides live in `src/content/docs/docs/`. The nested
`docs/` directory supplies the URL prefix without changing Astro's site-wide
`base`. Starlight styles are loaded only by the docs layout.

`starlight-openapi` generates `/docs/api/` and its operation pages from the
committed `../shroud.email/openapi.json`. See [Updating the OpenAPI specification](#updating-the-openapi-specification)
below for how to regenerate it from the Phoenix app's annotations and schemas.
Building the website needs only Node.js and pnpm, not Elixir or a database. The
specification is also published at `/docs/openapi.json`.

The `/docs/api/aliases/` and `/docs/api/domains/` URLs redirect to the generated
list-operation pages. Since this is a static build, Astro emits HTML redirect
pages rather than HTTP redirects. All other existing guide URLs are preserved.
Docs use the website's OpenPanel integration, Manrope font, and indigo
accent. Documentation is built and deployed with the website using the existing
website Bunny Storage and Pull Zones; no separate docs deployment is required.

### Analytics

Marketing and docs share `src/components/OpenPanel.astro`, using `@openpanel/astro`
with `https://panel.shroud.email/api` and `https://panel.shroud.email/op1.js`.
Set `PUBLIC_OPENPANEL_CLIENT_ID` at build time (for example, in `.env`). It is
public and included in the generated HTML. Missing or empty values omit tracking.
The production deployment reads it from the GitHub Actions repository variable
`OPENPANEL_CLIENT_ID`. Do not supply a client secret to the website build.
Screen views, outgoing links, and `data-track` attributes are enabled; session
replay and identification are not. The SDK retains normal marketing URLs and UTM
attribution. Do not add addresses, message content, or other private data to
tracking attributes or URLs. There are no page/event allowlists.

Development builds omit analytics. Production-built staging and local previews
reject events unless the browser origin is exactly `https://shroud.email`.
Text-request analytics is separately opt-in via Bunny runtime configuration;
see [edge analytics](edge-script/README.md#text-analytics).

Use `pnpm build` followed by `pnpm preview` to check Pagefind search, which needs
the production search index. `pnpm check:content-images` checks that the
custom-domain guide and existing marketing content retain their optimized images.

### Updating the OpenAPI specification

The Elixir annotations are the source of truth; `shroud.email/openapi.json` is a
generated snapshot, not edited by hand. After changing API annotations, install
the app's Mix dependencies and toolchain as described in
[`../shroud.email/README.md`](../shroud.email/README.md), then from `shroud.email/`:

```sh
mise exec -- mix openapi.spec.json --spec ShroudWeb.ApiSpec --start-app=false --pretty=true openapi.json
```

Commit the regenerated JSON alongside the source changes. The exporter compiles
the app but does not start it or require a database. To check it without rewriting
the file, from `shroud.email/`:

```sh
mise exec -- mix openapi.spec.json --spec ShroudWeb.ApiSpec --start-app=false --pretty=true --check=true openapi.json
```

CI runs this sync check in the Elixir test job. A separate Node-only job builds
the website and docs from the committed spec; spec changes also trigger the
website's production deployment on `main`.

### Editing documentation

- **Endpoint prose:** edit the Markdown `description` in the relevant
  `operation(...)` annotation in `../shroud.email/lib/shroud_web/controllers/api/v1/`.
- **Request/response fields and examples:** edit `Schemas` in that directory.
- **API introduction and authentication overview:** edit `ShroudWeb.ApiSpec` or
  the hand-written guides under `src/content/docs/docs/api/`, as appropriate.
- **Deployment, product guides and tutorials:** write Markdown/MDX pages under
  `src/content/docs/docs/`. Do not put these in the API specification.

Keep operation IDs stable: the plugin derives URLs from their lowercase values.
The existing controller tests check responses against the documented schemas.
Documentation annotations do not alter runtime request validation.

## Official Bunny website deployments

Both website workflows use the official `BunnyWay/actions/deploy-site` action
(0.1.1, SHA-pinned) with CLI 0.18.0, reusing existing zones:

| Environment | Storage Zone | Pull Zone | Name | Storage region |
| --- | --- | --- | --- | --- |
| Staging | 1687847 | 6214167 | `shroud-email-website-staging` | UK |
| Production | 1604565 | 6040372 | `shroud-email-website` | DE |

Deployments require the CLI's version-2 `_bunny/site.json` metadata on each pair.
Missing metadata requires deliberate recovery, not automatic reinitialization.

Production deploys on relevant `main` pushes. Staging is manual. Both workflows
also support manual deployment from GitHub's **Use workflow from** branch/tag
selector. Each run builds and deploys that event's exact commit for both the site
and middleware; there are no additional inputs or checkboxes.

```sh
# Deploy staging from main, or replace main with a branch to test.
gh workflow run website-deploy-staging.yml --ref main

# Manually deploy production from main.
gh workflow run website-deploy.yml --ref main
```

These commands change their target environment; they are not read-only checks.
The existing `BUNNY_API_KEY` secret must permit storage and Pull Zone API access.
The environment-specific script secrets are documented in
[the middleware README](edge-script/README.md#deployment).

Concurrency preserves the running deployment and keeps only the newest pending
request per environment. For distinct staging trials, wait for each run to finish
before dispatching the next; this workflow does not promise a FIFO deployment queue.

### Deployment behavior and checks

**Running either workflow changes its target:** the official action uploads under `deploys/<id>/`,
switches that site's routing, configures its custom 404, adds asset caching rules, and
purges its CDN cache. The CLI maintains its state/direct-deploy protection rules
and preserves unrelated custom rules.

Keep the existing **shroud: do not cache geo-localized pricing** rule enabled on
both Pull Zones. It sets edge and browser TTLs to zero and returns
`Cache-Control: no-store` for `/pricing`, `/pricing/`, and `/pricing/index.html`,
including query strings. Manage this rule in the Bunny dashboard; the official
CLI preserves it but does not recreate it if deleted. Keep **Run script before
cache** enabled for the middleware's missing-directory 404 fallback. The workflows
do not change that setting.

After publication, the workflow polls pricing for `no-store` before reporting
success. This verifies the runner's CDN location, not every POP or country.
If the check fails, publication has already happened; no automatic rollback occurs.
The middleware is deployed after the site job succeeds, followed by a complete
pricing GET check. Old deploys/root files are not pruned by these workflows.
`deployments: false` disables GitHub deployment records only; it does not disable
Bunny's versioned uploads, publication, or rollback support.

Check the [staging site](https://shroud-email-website-staging.b-cdn.net/), docs,
assets, missing-page behavior, `X-Bunny-Deploy`, and pricing from actual UK and
non-UK requests. Pricing should return `Cache-Control: no-store` and prices must not
leak across countries. A client-supplied country header alone is not proof of geo
isolation. Apply the same checks to production after deployment. Use a fresh
private window or clear the browser's target-site cache when verifying changes;
non-pricing pages can remain in the browser cache for 30 days.

Use the CLI's published-deployment rollback when needed. Do not delete Sites
metadata or versioned deployments outside the CLI. No automatic rollback or
destructive pruning is configured here.

## Want to learn more?

Feel free to check [the Astro documentation](https://github.com/withastro/astro).
