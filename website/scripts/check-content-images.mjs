import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const outputTargets = [
  { path: "../dist/blog/", minimumImages: 20 },
  { path: "../dist/docs/product/custom-domains/", minimumImages: 3 },
  { path: "../dist/vs/firefox-relay/", minimumImages: 1 },
];

async function findHtmlFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? findHtmlFiles(path) : [path];
    }),
  );

  return files.flat().filter((path) => path.endsWith(".html"));
}

const images = [];
const failures = [];

for (const target of outputTargets) {
  const outputDirectory = fileURLToPath(new URL(target.path, import.meta.url));
  const htmlFiles = await findHtmlFiles(outputDirectory);
  const targetImages = [];

  for (const htmlFile of htmlFiles) {
    const html = await readFile(htmlFile, "utf8");
    for (const [markup] of html.matchAll(/<img\b[^>]*>/g)) {
      targetImages.push({ htmlFile, markup });
    }
  }

  if (targetImages.length < target.minimumImages) {
    failures.push(
      `Expected at least ${target.minimumImages} images under ${outputDirectory}, found ${targetImages.length}.`,
    );
  }

  images.push(...targetImages);
}

for (const { htmlFile, markup } of images) {
  const label = `${htmlFile}: ${markup}`;
  const isPostHero = markup.includes("mb-12");
  const requiredAttributes = ["width", "height", "srcset", "sizes"];

  if (!/src="\/_astro\//.test(markup)) {
    failures.push(`Expected an Astro-generated image URL in ${label}`);
  }

  for (const attribute of requiredAttributes) {
    if (!new RegExp(`\\s${attribute}="[^"]+"`).test(markup)) {
      failures.push(`Expected ${attribute} on ${label}`);
    }
  }

  if (isPostHero) {
    if (!markup.includes('loading="eager"')) {
      failures.push(`Expected eager loading on post hero ${label}`);
    }
    if (!markup.includes('fetchpriority="high"')) {
      failures.push(`Expected high fetch priority on post hero ${label}`);
    }
  } else if (!markup.includes('loading="lazy"')) {
    failures.push(`Expected lazy loading on non-hero image ${label}`);
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Content image output check passed.");
}
