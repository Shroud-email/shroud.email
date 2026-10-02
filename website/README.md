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

## Official Bunny website deployments

Both website workflows use the official `BunnyWay/actions/deploy-site` action
(0.1.1, SHA-pinned) with CLI 0.18.0, reusing existing zones:

| Environment | Storage Zone | Pull Zone | Name | Storage region |
| --- | --- | --- | --- | --- |
| Staging | 1687847 | 6214167 | `shroud-email-website-staging` | UK |
| Production | 1604565 | 6040372 | `shroud-email-website` | DE |

No replacement zones are created. The old website uploader is removed;
the separate tracker-list uploader is unchanged.

This is an experimental adoption of existing zones, not an officially documented
import procedure. The small `scripts/adopt-bunny-site.mjs` bootstrap requires an
explicit `BUNNY_SITE_ENVIRONMENT` of `staging` or `production`, validates
the pair, adds the CLI's state-protection rule, verifies a public 403, and writes
version-2 `_bunny/site.json` only when initialization is explicitly requested and
both reads find it absent. This is not an atomic create-if-absent operation:
do not run another metadata writer concurrently. Initialization does not change
middleware attachment, domains, root files, or zone-wide cache overrides.
Every run checks state protection, restores a missing rule, and refuses a
conflicting or disabled rule before proceeding, without rewriting existing state.

To test before merging, dispatch the workflow **from this PR branch**, not `main`:

```sh
gh workflow run website-deploy-staging.yml \
  --ref feat/official-bunny-staging \
  -f ref=feat/official-bunny-staging \
  -f initialize_sites=false \
  -f deploy_edge_script=false
```

Both refs matter: the first selects the workflow definition, the second selects
the code to build. This command is for you to run; opening the PR does not deploy.
The existing repository `BUNNY_API_KEY` secret must permit storage and Pull Zone
API access. No new secrets or npm tooling are needed. Subsequent runs can leave
`initialize_sites=false` (staging is already adopted). A new pair requires an
explicit first run with `initialize_sites=true`. If rule propagation times out, no metadata is written;
the protection rule may remain and the same workflow can be retried.
Concurrency preserves the running deployment and keeps only the newest pending
request per environment. For distinct staging trials, wait for each run to finish
before dispatching the next; this workflow does not promise a FIFO deployment queue.

### First production cutover, before merging

Only an operator should dispatch this workflow; preparing or pushing the PR does
not deploy production. Schedule the cutover when no older production run is active
or queued, and avoid changes to `main` that trigger website deployment until the
PR is merged. The old `main` uploader would delete the newly adopted Sites state.

```sh
gh workflow run website-deploy.yml \
  --ref feat/official-bunny-staging \
  -f ref=feat/official-bunny-staging \
  -f initialize_sites=true \
  -f deploy_edge_script=true
```

This adopts the existing production pair and publishes the branch's website while
updating the attached production Edge script. First enable **Pull Zone → General
→ Origin → Run script before cache** on production for the missing-directory
404 fallback. Staging already has this setting enabled. It increases script
execution volume; the workflows do not enable it automatically.

If an old `main` deployment ran after adoption, its clean-delete uploader may
have removed Sites metadata. Use `initialize_sites=true` for this cutover: valid
existing metadata is checked and left unchanged, while absent metadata is
initialized. Do not run an old uploader between this trial and merging.

Verify home, docs, assets, 404,
state/direct-deploy protection, and UK/US pricing on `https://shroud.email` before
merging. After adoption, leave initialization off. Main pushes then deploy via the
official action and replace the Edge script only after the site job succeeds.
Main pushes refuse to initialize missing metadata automatically.

Staging remains manual after merging. To publish middleware cleanup there, run
the staging workflow with initialization off and `deploy_edge_script=true`.

### Deployment behavior and checks

**Running either workflow changes its target:** the official action uploads under `deploys/<id>/`,
switches that site's routing, configures its custom 404, adds asset caching rules, and
purges its CDN cache. Existing cache overrides and the attached Edge script remain
in place. Before deployment, the workflow upserts a target-specific rule to disable
edge and browser caching for `/pricing`, `/pricing/`, and `/pricing/index.html`
(including query strings), with a `Cache-Control: no-store` response header.
The deployment then purges existing cached pricing. Other paths and asset caching
are unchanged. The named pricing rule is workflow-owned: subsequent runs restore
its policy by GUID and refuse to duplicate an existing rule without a GUID.
After publication, the workflow polls pricing for `no-store` before reporting
success. This verifies the runner's CDN location, not every POP or country.
If the check fails, publication has already happened; no automatic rollback occurs.
Replacing that script is opt-in on manual runs (automatic on production main pushes) and only happens after site
deployment succeeds. Old deploys/root files are not pruned by this workflow.
`deployments: false` disables GitHub deployment records only; it does not disable
Bunny's versioned uploads, publication, or rollback support.

Check the [staging site](https://shroud-email-website-staging.b-cdn.net/), docs,
assets, missing-page behavior, `X-Bunny-Deploy`, and pricing from actual UK and
non-UK requests. Pricing should return `Cache-Control: no-store` and prices must not
leak across countries. A client-supplied country header alone is not proof of geo
isolation. Apply the same checks to production during its cutover.
After the first cache-protection deployment, test in a fresh private window or
clear the browser's target-site cache; a new response header cannot invalidate
an old browser entry cached for 30 days. Subsequent deployments should continue
to bypass pricing caches.

After adoption, **do not run an older website workflow using the clean-delete
uploader**: it would delete Sites metadata and versioned deployments. The first
adopted deployment has no CLI `--previous` rollback target; existing root files
remain, but returning to root serving requires a deliberate routing/404 rollback.
Later deployments can use the CLI's published-deployment rollback. No automatic
rollback or destructive pruning is configured here.

## Want to learn more?

Feel free to check [the Astro documentation](https://github.com/withastro/astro).
