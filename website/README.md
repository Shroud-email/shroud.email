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

The old `/docs/api/aliases/` and `/docs/api/domains/` URLs redirect to the generated
list-operation pages. Since this is a static build, Astro emits HTML redirect
pages rather than HTTP redirects. All other existing guide URLs are preserved.
Docs retain the shared cookieless PostHog integration, Manrope font, and indigo
accent. Documentation is built and deployed with the website using the existing
website Bunny Storage and Pull Zones; no separate docs deployment is required.

Use `pnpm build` followed by `pnpm preview` to check Pagefind search, which needs
the production search index. `pnpm check:content-images` checks that the moved
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

## Want to learn more?

Feel free to check [the Astro documentation](https://github.com/withastro/astro).
