// Publish the tracker list to a bunny.net Storage Zone and purge the Pull Zone cache.
//
// Required env vars:
//   BUNNY_STORAGE_PASSWORD  - storage zone read/write password (AccessKey)
//   BUNNY_PULLZONE_ID       - numeric Pull Zone id (for cache purge)
//   BUNNY_API_KEY           - account API key (for cache purge)

import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const ROOT = new URL('../', import.meta.url).pathname;
const ZONE = 'shroud-email-trackers';
const ENDPOINT = 'storage.bunnycdn.com';

// Files (relative to the repo root) to publish at the zone root.
const FILES = ['list.txt'];

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

const base = `https://${ENDPOINT}/${ZONE}`;

async function upload(path) {
  const body = await readFile(join(ROOT, path));
  const res = await fetch(`${base}/${path}`, {
    method: 'PUT',
    headers: { AccessKey: PASSWORD, 'Content-Type': 'application/octet-stream' },
    body,
  });
  if (!res.ok) throw new Error(`Upload ${path} failed: ${res.status} ${await res.text()}`);
  console.log(`  ↑ ${path}`);
}

async function purge() {
  const res = await fetch(`https://api.bunny.net/pullzone/${PULLZONE_ID}/purgeCache`, {
    method: 'POST',
    headers: { AccessKey: API_KEY },
  });
  if (!res.ok) throw new Error(`Purge failed: ${res.status} ${await res.text()}`);
}

console.log(`Uploading ${FILES.length} file(s) to ${ZONE}…`);
for (const path of FILES) await upload(path);

console.log('Purging Pull Zone cache…');
await purge();

console.log('Done.');
