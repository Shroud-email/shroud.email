# Shroud.email documentation

Standalone Astro Starlight site for `https://docs.shroud.email`. Product and
deployment guides live in `src/content/docs/`; API reference pages are generated
by `starlight-openapi` from `public/openapi.json`.

## Build and preview

Install the app's Mix dependencies and toolchain as described in
[`../shroud.email/README.md`](../shroud.email/README.md). Then, from `shroud.email/`:

```sh
mise exec -- mix openapi.spec.json --spec ShroudWeb.ApiSpec --start-app=false --pretty=true ../docs-site/public/openapi.json
```

The exporter compiles the app but does not start it or require a database. From
`docs-site/`:

```sh
mise trust
mise install
mise exec -- pnpm install --frozen-lockfile
mise exec -- pnpm build
mise exec -- pnpm dev
```

Regenerate the spec after changing API annotations. CI generates it before every
docs build. The JSON and build output are ignored; neither is a second source of
truth.

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

## Deployment and cutover

`.github/workflows/docs-deploy.yml` automatically generates the spec, builds the
site and publishes `dist/` to Bunny Storage on changes to docs or app source on
`main`. It also supports manual dispatch on `main`; pull requests only build and
never deploy. The uploader publishes Bunny's custom 404 page and purges the Pull
Zone cache. No Node.js server is required in production.

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

Uploader tests use mocked HTTP requests and disposable local fixtures:

```sh
node --test ../website/scripts/deploy-bunny.test.mjs
```

Once the docs domain is live, update the marketing site's docs links and configure
permanent redirects for the old `/docs/` URLs. Product/deployment paths map to the
same paths without `/docs`; the old aliases/domains pages should map to their
generated list-operation pages, and authentication to `/api/authentication/`.
