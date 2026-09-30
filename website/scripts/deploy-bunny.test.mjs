import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const script = new URL("./deploy-bunny.mjs", import.meta.url).href;

function deploy(cwd, env = {}, scriptUrl = script) {
  return spawnSync(process.execPath, ["--input-type=module", "--eval", `
    const calls = [];
    globalThis.fetch = async (url, options = {}) => {
      calls.push({url, method: options.method || 'GET', contentType: options.headers?.['Content-Type'], body: options.body?.toString()});
      if (url === 'https://api.bunny.net/storagezone') {
        return Response.json([{Name: 'docs-test', Region: 'uk'}]);
      }
      if ((options.method || 'GET') === 'GET') {
        return Response.json([{ObjectName: 'old-page.html', IsDirectory: false}]);
      }
      return new Response('', {status: 200});
    };
    try {
      await import(${JSON.stringify(scriptUrl)});
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    } finally {
      console.log('REQUESTS:' + JSON.stringify(calls));
    }
  `], {
    cwd,
    encoding: "utf8",
    env: {
      ...process.env,
      BUNNY_DIST: "dist",
      BUNNY_STORAGE_ZONE: "docs-test",
      BUNNY_STORAGE_PASSWORD: "test-storage-password",
      BUNNY_PULLZONE_ID: "456",
      BUNNY_API_KEY: "test-account-key",
      BUNNY_STORAGE_ENDPOINT: "",
      ...env,
    },
  });
}

function requests(result) {
  const line = result.stdout.split("\n").find((line) => line.startsWith("REQUESTS:"));
  return JSON.parse(line.slice("REQUESTS:".length));
}

test("uploads the custom build only to its own regional zone, then purges its cache", async (t) => {
  const cwd = await mkdtemp(join(tmpdir(), "bunny-docs-"));
  t.after(() => rm(cwd, { recursive: true, force: true }));
  await mkdir(join(cwd, "dist", "api"), { recursive: true });
  await writeFile(join(cwd, "dist", "api", "index.html"), "Docs API page");
  await writeFile(join(cwd, "dist", "openapi.json"), '{"openapi":"3.0.0"}');
  await writeFile(join(cwd, "dist", "404.html"), "Docs not found");

  const result = deploy(cwd);
  assert.equal(result.status, 0, result.stderr);
  const calls = requests(result);
  const uploads = calls.filter((call) => call.method === "PUT");
  assert.deepEqual(uploads.map((call) => new URL(call.url).pathname).sort(), [
    "/docs-test/404.html",
    "/docs-test/api/index.html",
    "/docs-test/bunnycdn_errors/404.html",
    "/docs-test/openapi.json",
  ]);
  assert.ok(uploads.every((call) => new URL(call.url).host === "uk.storage.bunnycdn.com"));
  assert.equal(uploads.find((call) => call.url.endsWith("/api/index.html")).body, "Docs API page");
  assert.equal(uploads.find((call) => call.url.endsWith("/openapi.json")).contentType, "application/json; charset=utf-8");
  assert.equal(uploads.find((call) => call.url.endsWith("/bunnycdn_errors/404.html")).body, "Docs not found");
  assert.equal(calls.find((call) => call.method === "DELETE").url, "https://uk.storage.bunnycdn.com/docs-test/old-page.html");
  assert.deepEqual(calls.at(-1), {url: "https://api.bunny.net/pullzone/456/purgeCache", method: "POST"});
});

test("the marketing default still uses the script-relative dist and existing zone", async (t) => {
  const cwd = await mkdtemp(join(tmpdir(), "bunny-website-"));
  t.after(() => rm(cwd, { recursive: true, force: true }));
  const site = join(cwd, "website");
  await mkdir(join(site, "scripts"), { recursive: true });
  await mkdir(join(site, "dist"));
  await writeFile(join(site, "dist", "404.html"), "Marketing not found");
  const copy = join(site, "scripts", "deploy-bunny.mjs");
  await writeFile(copy, await readFile(new URL(script)));
  const result = deploy(cwd, {
    BUNNY_DIST: "",
    BUNNY_STORAGE_ZONE: "",
    BUNNY_STORAGE_ENDPOINT: "storage.bunnycdn.com",
  }, pathToFileURL(copy).href);
  assert.equal(result.status, 0, result.stderr);
  const uploads = requests(result).filter((call) => call.method === "PUT");
  assert.deepEqual(uploads.map((call) => call.url).sort(), [
    "https://storage.bunnycdn.com/shroud-email-website/404.html",
    "https://storage.bunnycdn.com/shroud-email-website/bunnycdn_errors/404.html",
  ]);
  assert.ok(uploads.every((call) => call.body === "Marketing not found"));
});

test("a custom build cannot fall back to the marketing storage zone", async (t) => {
  const cwd = await mkdtemp(join(tmpdir(), "bunny-docs-"));
  t.after(() => rm(cwd, { recursive: true, force: true }));
  const result = deploy(cwd, { BUNNY_STORAGE_ZONE: "" });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /requires an explicit BUNNY_STORAGE_ZONE/);
  assert.deepEqual(requests(result), []);
});

test("missing, empty or incomplete local builds never contact Bunny", async (t) => {
  const cwd = await mkdtemp(join(tmpdir(), "bunny-docs-"));
  t.after(() => rm(cwd, { recursive: true, force: true }));
  for (const state of ["missing", "empty", "no-404"]) {
    if (state === "empty") await mkdir(join(cwd, "dist"));
    if (state === "no-404") await writeFile(join(cwd, "dist", "index.html"), "Docs");
    const result = deploy(cwd);
    assert.equal(result.status, 1, state);
    assert.deepEqual(requests(result), [], state);
  }
});
