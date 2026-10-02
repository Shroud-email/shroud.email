import { defineCollection } from "astro:content";
import { docsLoader } from "@astrojs/starlight/loaders";
import { docsSchema } from "@astrojs/starlight/schema";
import { glob } from "astro/loaders";
import { z } from "astro/zod";

const blogCollection = defineCollection({
  loader: glob({
    pattern: "**/[^_]*.{md,mdx}",
    base: "./src/content/blog",
    generateId: ({ entry }) =>
      entry.replace(/\.(md|mdx)$/, "").replace(/^\d{4}-\d{2}-\d{2}-/, ""),
  }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      description: z.string(),
      date: z.date(),
      image: image(),
      imageAlt: z.string(),
    }),
});
const docsCollection = defineCollection({
  loader: docsLoader(),
  schema: docsSchema(),
});

export const collections = {
  blog: blogCollection,
  docs: docsCollection,
};
