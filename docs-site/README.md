# Shroud.email documentation

Standalone Astro Starlight site for `https://docs.shroud.email`. Product and
deployment guides live in `src/content/docs/`; API reference pages are generated
by `starlight-openapi` from the committed `../shroud.email/openapi.json`.

## Build and preview

Building or editing the docs only requires Node.js and pnpm, not Elixir or a
database. From `docs-site/`:

```sh
mise trust
mise install
mise exec -- pnpm install --frozen-lockfile
mise exec -- pnpm build
mise exec -- pnpm dev
```

## Updating the OpenAPI specification

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

CI runs this sync check in the existing Elixir test job and fails if the committed
spec differs from the generated output. A separate Node-only job builds the docs
in parallel using the committed spec. Build output remains ignored.

## Editing documentation

- **Endpoint prose:** edit the Markdown `description` in the relevant
  `operation(...)` annotation in `../shroud.email/lib/shroud_web/controllers/api/v1/`.
- **Request/response fields and examples:** edit `Schemas` in that directory.
- **API introduction and authentication overview:** edit `ShroudWeb.ApiSpec` or
  the hand-written guides under `src/content/docs/api/`, as appropriate.
- **Deployment, product guides and tutorials:** write Markdown/MDX pages under
  `src/content/docs/`. Do not put these in the API specification.

Keep operation IDs stable: the plugin derives URLs from their lowercase values.
The existing controller tests check responses against the documented schemas.
Documentation annotations do not alter runtime request validation.

## Analytics

Both the docs and marketing site use `../shared/components/PostHog.astro`, with
the same PostHog project, proxy endpoint, and `cookieless_mode: "always"` setting.
The SDK loads after the page is ready and the browser is idle.

Cookieless mode does not persist visitor IDs in cookies or browser storage.
PostHog's server-side hash includes the hostname and a daily salt, so anonymous
IDs are not shared between `shroud.email` and `docs.shroud.email`. Persistent
cross-subdomain IDs would require a separate cookie/consent or identification
policy; this integration does not change the existing privacy behavior.

## Deployment and cutover

`.github/workflows/docs-deploy.yml` builds the site from the committed spec and
publishes `dist/` to Bunny Storage on changes to docs, the spec, shared analytics,
or deployment tooling on `main`. Deployment requires only Node.js and pnpm, not
Elixir. It also supports manual dispatch on `main`; pull requests only build and
never deploy. The uploader publishes Bunny's custom 404 page and purges the Pull
Zone cache. Both sites use the shared `../scripts/deploy-bunny.mjs` uploader.
No Node.js server is required in production.

Create a **dedicated** Bunny Storage Zone and connected Pull Zone for the docs.
Attach `docs.shroud.email`, configure its DNS/TLS, enable directory index serving
(`index.html`) and enable the custom error page. Keep the existing marketing
website's zones unchanged. Configure these GitHub repository settings:

| Setting | Type | Value |
| --- | --- | --- |
| `DOCS_BUNNY_STORAGE_ZONE` | Actions variable | Dedicated docs Storage Zone name |
| `DOCS_BUNNY_STORAGE_PASSWORD` | Actions secret | That zone's read/write password |
| `DOCS_BUNNY_PULLZONE_ID` | Actions secret | Connected docs Pull Zone ID |
| `BUNNY_API_KEY` | Actions secret | Existing account API key for region lookup and cache purge |

The region is detected automatically. Missing settings fail the deployment; a
custom build directory cannot fall back to the marketing-site zone. The uploader
checks the local build before clearing the destination, then replaces its contents
and purges the cache. Deployments run serially to avoid partial cancelled uploads.

Once the docs domain is live, update the marketing site's docs links and configure
permanent redirects for the old `/docs/` URLs. Product/deployment paths map to the
same paths without `/docs`; the old aliases/domains pages should map to their
generated list-operation pages, and authentication to `/api/authentication/`.
