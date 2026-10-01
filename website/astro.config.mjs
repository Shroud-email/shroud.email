import vue from "@astrojs/vue";
import icon from "astro-icon";
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";
import mdx from "@astrojs/mdx";
import starlight from "@astrojs/starlight";
import starlightOpenAPI, { openAPISidebarGroups } from "starlight-openapi";

// https://astro.build/config
export default defineConfig({
  site: "https://shroud.email/",
  compressHTML: true,
  server: { allowedHosts: [".onamp.dev"] },
  redirects: {
    "/docs/api/aliases/": "/docs/api/operations/listaliases/",
    "/docs/api/domains/": "/docs/api/operations/listdomains/",
  },

  integrations: [
    vue(),
    icon(),
    sitemap({
      filter: (page) => page !== "https://shroud.email/newsletter-success/",
    }),
    starlight({
      title: "Shroud.email",
      description:
        "Product, deployment, and API documentation for Shroud.email.",
      favicon: "/favicon.ico",
      disable404Route: true,
      customCss: ["./src/styles/docs.css"],
      expressiveCode: { defaultProps: { wrap: true } },
      components: { Head: "./src/components/DocsHead.astro" },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/Shroud-email/shroud.email",
        },
      ],
      plugins: [
        starlightOpenAPI([
          {
            base: "docs/api",
            schema: "../shroud.email/openapi.json",
            sidebar: { label: "API reference", collapsed: false },
          },
        ]),
      ],
      sidebar: [
        { label: "Welcome", link: "/docs/" },
        {
          label: "Product guides",
          items: [{ autogenerate: { directory: "docs/product" } }],
        },
        {
          label: "Deployment",
          items: [
            { slug: "docs/deployment/considerations" },
            { slug: "docs/deployment/self-host" },
            { slug: "docs/deployment/upgrading" },
          ],
        },
        {
          label: "Using the API",
          items: [
            { slug: "docs/api/overview" },
            { slug: "docs/api/authentication" },
          ],
        },
        ...openAPISidebarGroups,
      ],
    }),
    mdx(),
  ],

  vite: {
    plugins: [tailwindcss()],
    ssr: {
      external: ["svgo"],
    },
    environments: {
      ssr: {
        optimizeDeps: {
          include: ["debug"],
        },
      },
      prerender: {
        optimizeDeps: {
          include: ["debug"],
        },
      },
    },
  },

  trailingSlash: "always",
});
