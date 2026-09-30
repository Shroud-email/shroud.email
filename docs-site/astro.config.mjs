import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightOpenAPI, { openAPISidebarGroups } from "starlight-openapi";

export default defineConfig({
  site: "https://docs.shroud.email",
  trailingSlash: "always",
  server: { allowedHosts: [".onamp.dev"] },
  integrations: [
    starlight({
      title: "Shroud.email",
      description: "Product, deployment, and API documentation for Shroud.email.",
      customCss: ["./src/styles/brand.css"],
      components: { Head: "./src/components/Head.astro" },
      social: [{ icon: "github", label: "GitHub", href: "https://github.com/Shroud-email/shroud.email" }],
      plugins: [
        starlightOpenAPI([
          {
            base: "api",
            schema: "./public/openapi.json",
            sidebar: { label: "API reference", collapsed: false },
          },
        ]),
      ],
      sidebar: [
        { label: "Welcome", slug: "index" },
        { label: "Product guides", autogenerate: { directory: "product" } },
        {
          label: "Deployment",
          items: [
            { slug: "deployment/considerations" },
            { slug: "deployment/self-host" },
            { slug: "deployment/upgrading" },
          ],
        },
        {
          label: "Using the API",
          items: [{ slug: "api/overview" }, { slug: "api/authentication" }],
        },
        ...openAPISidebarGroups,
      ],
    }),
  ],
});
