// Publish the built site (dist/client) to a bunny.net Storage Zone and purge
// the Pull Zone cache.
//
// Performs a clean deploy: the existing zone contents are deleted first so that
// removed pages and stale hashed assets don't linger.
//
// Required env vars:
//   BUNNY_STORAGE_PASSWORD  - storage zone read/write password (AccessKey)
//   BUNNY_PULLZONE_ID       - numeric Pull Zone id (for cache purge)
//   BUNNY_API_KEY           - account API key (for cache purge + region lookup)
//
// Optional env vars:
//   BUNNY_STORAGE_ZONE      - storage zone name (default: shroud-email-website).
//                            Set to shroud-email-website-staging for staging deploys.
//   BUNNY_STORAGE_ENDPOINT  - storage endpoint for the zone's region. If set,
//                            overrides auto-detection. Otherwise the script
//                            looks up the zone's region via the bunny API and
//                            maps it to the correct regional endpoint
//                            (e.g. ny.storage.bunnycdn.com for New York).

import { readFile, readdir } from "node:fs/promises";
import { join, relative, extname } from "node:path";

// Map bunny storage region codes to their HTTP API endpoints. The default
// (Falkenstein / Frankfurt, DE) has no prefix.
// Ref: https://docs.bunny.net/storage/http
const REGION_ENDPOINTS = {
  de: "storage.bunnycdn.com",
  uk: "uk.storage.bunnycdn.com",
  ny: "ny.storage.bunnycdn.com",
  la: "la.storage.bunnycdn.com",
  sg: "sg.storage.bunnycdn.com",
  se: "se.storage.bunnycdn.com",
  br: "br.storage.bunnycdn.com",
  jh: "jh.storage.bunnycdn.com",
  syd: "syd.storage.bunnycdn.com",
};

const ROOT = new URL("../", import.meta.url).pathname;

// Directory (relative to the repo root) holding the static site to publish.
const DIST = join(ROOT, "dist");

// Storage zone name. Defaults to the production zone; override with
// BUNNY_STORAGE_ZONE for staging (e.g. shroud-email-website-staging).
const ZONE = process.env.BUNNY_STORAGE_ZONE || "shroud-email-website";

const {
  BUNNY_STORAGE_PASSWORD: PASSWORD,
  BUNNY_PULLZONE_ID: PULLZONE_ID,
  BUNNY_API_KEY: API_KEY,
} = process.env;

for (const [name, value] of Object.entries({
  BUNNY_STORAGE_PASSWORD: PASSWORD,
  BUNNY_PULLZONE_ID: PULLZONE_ID,
  BUNNY_API_KEY: API_KEY,
})) {
  if (!value) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
}

// Resolve the storage endpoint for the zone's region. If BUNNY_STORAGE_ENDPOINT
// is set, use it as an override. Otherwise look the zone up via the bunny API
// (using the account API key) and map its Region to the right endpoint. A
// correct endpoint is required: the storage password only authenticates
// against the zone's primary region, so hitting the wrong regional endpoint
// returns 401 even with a valid password.
async function resolveStorageEndpoint() {
  if (process.env.BUNNY_STORAGE_ENDPOINT) return process.env.BUNNY_STORAGE_ENDPOINT;

  try {
    const res = await fetch("https://api.bunny.net/storagezone", {
      headers: { AccessKey: API_KEY },
    });
    if (!res.ok) {
      throw new Error(`${res.status} ${await res.text()}`);
    }
    const zones = await res.json();
    const zone = (Array.isArray(zones) ? zones : []).find((z) => z.Name === ZONE);
    if (!zone) {
      throw new Error(`zone "${ZONE}" not found in account`);
    }
    const region = (zone.Region || "de").toLowerCase();
    const endpoint = REGION_ENDPOINTS[region];
    if (!endpoint) {
      throw new Error(`unknown region "${region}" for zone "${ZONE}"`);
    }
    return endpoint;
  } catch (err) {
    console.warn(
      `Could not auto-detect storage region for zone "${ZONE}" (${err.message}). ` +
        "Falling back to the default endpoint (Falkenstein, DE). If deploys fail " +
        "with 401, set BUNNY_STORAGE_ENDPOINT to your zone's regional endpoint.",
    );
    return "storage.bunnycdn.com";
  }
}

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".avif": "image/avif",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".webmanifest": "application/manifest+json",
  ".pdf": "application/pdf",
};

const contentType = (path) => MIME[extname(path).toLowerCase()] || "application/octet-stream";

// Recursively collect every file under `dir`, skipping dotfiles such as
// .DS_Store (macOS) and .assetsignore (Cloudflare-specific).
async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const abs = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(abs)));
    else files.push(abs);
  }
  return files;
}

// List the immediate contents of a storage path (must end with "/").
async function list(base, path = "") {
  const res = await fetch(`${base}${path}`, { headers: { AccessKey: PASSWORD } });
  if (res.status === 404) return [];
  if (!res.ok) throw new Error(`List ${path} failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function remove(base, path) {
  const res = await fetch(`${base}${path}`, {
    method: "DELETE",
    headers: { AccessKey: PASSWORD },
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`Delete ${path} failed: ${res.status} ${await res.text()}`);
  }
}

async function put(base, rel, body) {
  const res = await fetch(`${base}${rel}`, {
    method: "PUT",
    headers: { AccessKey: PASSWORD, "Content-Type": contentType(rel) },
    body,
  });
  if (!res.ok) throw new Error(`Upload ${rel} failed: ${res.status} ${await res.text()}`);
  return rel;
}

async function upload(base, abs) {
  const rel = relative(DIST, abs).split(/[/\\]/).join("/");
  return put(base, rel, await readFile(abs));
}

async function purge() {
  const res = await fetch(`https://api.bunny.net/pullzone/${PULLZONE_ID}/purgeCache`, {
    method: "POST",
    headers: { AccessKey: API_KEY },
  });
  if (!res.ok) throw new Error(`Purge failed: ${res.status} ${await res.text()}`);
}

// Run async tasks with a bounded concurrency so large deploys stay fast
// without opening hundreds of sockets at once.
async function pool(items, limit, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) {
      const item = items[i++];
      await fn(item);
    }
  });
  await Promise.all(workers);
}

const endpoint = await resolveStorageEndpoint();
console.log(`Using storage endpoint ${endpoint} for zone ${ZONE}`);
const base = `https://${endpoint}/${ZONE}/`;

console.log(`Cleaning storage zone ${ZONE}…`);
const existing = await list(base, "");
await pool(existing, 8, (item) =>
  remove(base, item.IsDirectory ? `${item.ObjectName}/` : item.ObjectName),
);

const files = await walk(DIST);
console.log(`Uploading ${files.length} file(s) to ${ZONE}…`);
let done = 0;
await pool(files, 10, async (abs) => {
  await upload(base, abs);
  done++;
});
console.log(`  ↑ ${done} uploaded`);

// Bunny serves a custom 404 only from bunnycdn_errors/404.html at the zone
// root, so publish the built 404 page there too.
console.log("Publishing custom 404 page…");
await put(base, "bunnycdn_errors/404.html", await readFile(join(DIST, "404.html")));

console.log("Purging Pull Zone cache…");
await purge();

console.log("Done.");
