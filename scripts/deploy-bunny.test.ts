import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

// Redirect the fixed website build path to a disposable fixture, without
// changing the publisher's production build-directory contract.
const fixture = vi.hoisted(() => ({ dist: "" }));
vi.mock("node:fs/promises", async (importOriginal) => {
  const fs = await importOriginal<typeof import("node:fs/promises")>();
  const { join, relative } = await import("node:path");
  const build = new URL("../website/dist/", import.meta.url).pathname;
  return {
    ...fs,
    readdir: (path: string, options: { withFileTypes: true }) =>
      fs.readdir(join(fixture.dist, relative(build, path)), options),
    readFile: (path: string) => fs.readFile(join(fixture.dist, relative(build, path))),
  };
});

type Entry = { ObjectName: string; IsDirectory: boolean };
type Request = { method: string; path: string; body?: string };
const file = (ObjectName: string): Entry => ({ ObjectName, IsDirectory: false });
const dir = (ObjectName: string): Entry => ({ ObjectName, IsDirectory: true });
const listings: Record<string, Entry[]> = {
  "": [file("index.html"), file("404.html"), file("removed.html"), dir("assets"), dir("bunnycdn_errors"), dir("old")],
  "assets/": [file("new.js"), file("stale.js")],
  "bunnycdn_errors/": [file("404.html")],
  "old/": [dir("nested")],
  "old/nested/": [file("removed.html")],
};
const base = "https://storage.example/test-zone/";
const purgeURL = "https://api.bunny.net/pullzone/123/purgeCache";
let dist: string;
let requests: Request[];

beforeEach(async () => {
  vi.resetModules();
  requests = [];
  dist = await mkdtemp(join(tmpdir(), "bunny-deploy-"));
  await mkdir(join(dist, "assets"));
  await writeFile(join(dist, "index.html"), "new homepage");
  await writeFile(join(dist, "404.html"), "new not found");
  await writeFile(join(dist, "assets", "new.js"), "new asset");
  fixture.dist = dist;
  vi.stubEnv("BUNNY_STORAGE_ZONE", "test-zone");
  vi.stubEnv("BUNNY_STORAGE_ENDPOINT", "storage.example");
  vi.stubEnv("BUNNY_STORAGE_PASSWORD", "test-password");
  vi.stubEnv("BUNNY_PULLZONE_ID", "123");
  vi.stubEnv("BUNNY_API_KEY", "test-key");
  vi.spyOn(console, "log").mockImplementation(() => {});
});

afterEach(async () => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
  await rm(dist, { recursive: true, force: true });
});

function mockStorage(intercept?: (request: Request) => Promise<Response> | undefined) {
  vi.stubGlobal("fetch", vi.fn(async (url: string, options: RequestInit = {}) => {
    const request = {
      method: options.method || "GET",
      path: url.startsWith(base) ? url.slice(base.length) : url,
      body: options.body?.toString(),
    };
    requests.push(request);
    const response = intercept?.(request);
    if (response) return response;
    if (request.method === "GET" && request.path in listings) {
      return Response.json(listings[request.path]);
    }
    if (request.method === "PUT" && url.startsWith(base)) return new Response("");
    if (request.method === "DELETE" && url.startsWith(base)) return new Response("");
    if (request.method === "POST" && url === purgeURL) return new Response("");
    throw new Error(`Unexpected request: ${request.method} ${url}`);
  }));
}

const deploy = () => import("./deploy-bunny.ts");

test("uploads everything before deleting only stale files, then purges", async () => {
  mockStorage();
  await deploy();
  expect(requests.filter((r) => r.method === "PUT").map((r) => r.path).sort()).toEqual(
    ["404.html", "assets/new.js", "bunnycdn_errors/404.html", "index.html"],
  );
  expect(requests.find((r) => r.path === "bunnycdn_errors/404.html")?.body).toBe("new not found");
  expect(requests.filter((r) => r.method === "DELETE").map((r) => r.path).sort()).toEqual(
    ["assets/stale.js", "old/nested/removed.html", "removed.html"],
  );
  expect(requests.findIndex((r) => r.method === "GET" || r.method === "DELETE")).toBe(4);
  expect(requests.at(-1)).toMatchObject({ method: "POST", path: purgeURL });
});

test.each(["assets/new.js", "bunnycdn_errors/404.html"])(
  "failed upload of %s skips cleanup and purge", async (path) => {
    mockStorage((r) => r.method === "PUT" && r.path === path
      ? Promise.resolve(new Response("simulated failure", { status: 500 })) : undefined);
    await expect(deploy()).rejects.toThrow(`Upload ${path} failed: 500 simulated failure`);
    // A rejected pool can still have sibling uploads in flight; let them finish
    // before restoring the mocked HTTP boundary for the next test.
    await vi.waitFor(() => {
      expect(requests.filter((r) => r.method === "PUT" && r.path !== "bunnycdn_errors/404.html")).toHaveLength(3);
    });
    expect(requests.some((r) => r.path === path)).toBe(true);
    expect(requests.every((r) => r.method === "PUT")).toBe(true);
  },
);

test.each(["GET old/nested/", "DELETE assets/stale.js"])(
  "failed cleanup request %s skips purge", async (failure) => {
    mockStorage((r) => `${r.method} ${r.path}` === failure
      ? Promise.resolve(new Response("simulated failure", { status: 500 })) : undefined);
    await expect(deploy()).rejects.toThrow(/(?:List|Delete) .* failed: 500 simulated failure/);
    expect(requests.some((r) => r.method === "POST")).toBe(false);
    if (failure.startsWith("GET")) {
      expect(requests.some((r) => r.method === "DELETE")).toBe(false);
    }
  },
);

test.each([
  ["PUT", "assets/new.js", "GET"],
  ["PUT", "bunnycdn_errors/404.html", "GET"],
  ["DELETE", "assets/stale.js", "POST"],
])("waits for %s %s to finish before %s", async (method, path, nextMethod) => {
  let release!: (response: Response) => void;
  const heldResponse = new Promise<Response>((resolve) => { release = resolve; });
  mockStorage((r) => r.method === method && r.path === path ? heldResponse : undefined);
  const deployment = deploy();
  try {
    await vi.waitFor(() => {
      expect(requests.some((r) => r.method === method && r.path === path)).toBe(true);
    });
    // Give an incorrectly unawaited next phase time to run while the response is held.
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(requests.some((r) => r.method === nextMethod)).toBe(false);
  } finally {
    release(new Response(""));
    await deployment;
  }
  expect(requests.some((r) => r.method === nextMethod)).toBe(true);
});
