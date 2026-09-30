import vue from "@astrojs/vue";
import icon from "astro-icon";
import { defineConfig } from 'astro/config';
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";
import mdx from "@astrojs/mdx";

// https://astro.build/config
export default defineConfig({
  site: "https://shroud.email/",
  compressHTML: true,

  integrations: [vue(), icon(), sitemap({
    filter: page => page !== 'https://shroud.email/newsletter-success/'
  }), mdx()],

  vite: {
    plugins: [tailwindcss()],
    ssr: {
      external: ["svgo"]
    },
    environments: {
      ssr: {
        optimizeDeps: {
          include: ["debug"]
        }
      },
      prerender: {
        optimizeDeps: {
          include: ["debug"]
        }
      }
    }
  },

  trailingSlash: "always",
});
