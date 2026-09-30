import assert from "node:assert/strict";
import test from "node:test";

process.env.BUNNY_STORAGE_PASSWORD = "test";
process.env.BUNNY_PULLZONE_ID = "1";
process.env.BUNNY_API_KEY = "test";

const { listFiles, publishFiles } = await import("./deploy-bunny.mjs");

test("recursively inventories files without deleting directories", async (t) => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(url);
    const path = new URL(url).pathname.replace("/zone/", "");
    const body =
      path === ""
        ? [{ ObjectName: "index.html", IsDirectory: false }, { ObjectName: "assets", IsDirectory: true }]
        : [{ ObjectName: "assets/app.js", IsDirectory: false }];
    return new Response(JSON.stringify(body));
  };
  t.after(() => delete globalThis.fetch);

  assert.deepEqual(await listFiles("https://storage.example/zone/"), ["index.html", "assets/app.js"]);
  assert.deepEqual(calls, ["https://storage.example/zone/", "https://storage.example/zone/assets/"]);
});

test("listing errors preserve their operation and path", async (t) => {
  globalThis.fetch = async () => new Response("upstream detail", { status: 503 });
  t.after(() => delete globalThis.fetch);

  await assert.rejects(
    listFiles("https://storage.example/zone/", "nested/"),
    /List nested\/ failed: 503 upstream detail/,
  );
});

test("uploads everything before removing only stale files", async () => {
  const operations = [];
  const stale = await publishFiles(["keep.html", "old.html", "old/deep.js"], ["keep.html", "new.js"], {
    uploadFile: async (path) => operations.push(`put:${path}`),
    upload404: async () => operations.push("put:bunnycdn_errors/404.html"),
    deleteFile: async (path) => operations.push(`delete:${path}`),
  });

  assert.deepEqual(stale, ["old.html", "old/deep.js"]);
  assert.deepEqual(operations, [
    "put:keep.html",
    "put:new.js",
    "put:bunnycdn_errors/404.html",
    "delete:old.html",
    "delete:old/deep.js",
  ]);
});

test("an upload failure is preserved and prevents deletion", async () => {
  const failure = new Error("Upload new.js failed: 503 origin unavailable");
  let deleted = false;

  await assert.rejects(
    publishFiles(["old.html"], ["new.js"], {
      uploadFile: async () => {
        throw failure;
      },
      upload404: async () => {},
      deleteFile: async () => {
        deleted = true;
      },
    }),
    (error) => error === failure,
  );
  assert.equal(deleted, false);
});
