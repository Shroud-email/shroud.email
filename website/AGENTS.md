# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Marketing/docs website for [Shroud.email](https://shroud.email), an email privacy service. Built with Astro 6, Vue 3, Tailwind CSS v4, and deployed to Cloudflare Workers/Pages.

## Commands

- `npm run dev` — local dev server
- `npm run build` — type-check (`astro check` + `vue-tsc --noEmit`) then build
- `npm run preview` — serve production build locally
- `npm run lint` — format + lint with Biome (auto-fixes)

No test framework is configured. Verify changes with `npm run build`.

## Architecture

**Rendering:** Hybrid — Astro defaults to static prerendering, with Cloudflare adapter for SSR-capable routes. All URLs use trailing slashes (`trailingSlash: "always"` in astro config).

**Component model:** Pages are `.astro` files; interactive components use Vue (`.vue`). Components follow atomic design:
- `src/components/atoms/` — small primitives (Alert, FadeIn, Prose, ScrollingText)
- `src/components/molecules/` — composed UI (NavbarDropdown, NewsletterForm, PageHeader, PostPreview)
- `src/components/organisms/` — page sections (HeroSection, Pricing, Footer, navbar, FeatureSection)

**Layouts:** `src/layouts/` — `BaseLayout` is the root (includes SEO, PostHog analytics, fonts). `LandingLayout`, `BlogPost`, `DocsLayout`, and `ComparisonLayout` extend it.

**Content collections:** Defined in `src/content.config.ts` using Astro's glob loader:
- `blog` — `src/content/blog/*.md` (schema: title, description, date, image, imageAlt)
- `docs` — `src/content/docs/**/*.md` (schema: title, description; organized into api/, deployment/, product/ subdirs)

**Pages:** `src/pages/` — static marketing pages plus dynamic routes:
- `blog/[slug].astro` and `blog/index.astro` — blog listing and posts
- `docs/[...slug].astro` — docs catch-all route
- `vs/` — comparison pages (e.g., `vs/firefox-relay.md`)
- `blog/rss.xml.ts` — RSS feed

**Site config:** `src/config.ts` exports `SITE` and `OPEN_GRAPH` constants used by BaseLayout for SEO/meta.

**Path alias:** `~/` maps to `src/` (configured in tsconfig.json).

## Coding Conventions

- 2-space indentation, double quotes (enforced by Biome)
- Components: PascalCase filenames. Pages/routes: kebab-case
- Biome only lints `src/**/*` and root config files; `.astro`/`.vue` files have relaxed rules (useConst, useImportType, unused vars/imports off)
- Fonts: Manrope (body), Fraunces (headings) — self-hosted from `src/assets/fonts/`
- Tailwind v4 uses the Vite plugin (`@tailwindcss/vite`), not PostCSS. Global styles in `src/styles/tailwind.css`

## Deployment

Cloudflare Workers/Pages via `wrangler.jsonc`. Assets served from `dist/` with 404-page handling.
