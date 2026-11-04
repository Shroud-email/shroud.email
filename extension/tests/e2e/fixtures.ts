import {
  test as base,
  chromium,
  type BrowserContext,
  type Page,
} from "@playwright/test";
import { createServer } from "node:http";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

export const test = base.extend<{
  extension: {
    context: BrowserContext;
    popup: Page;
    website: string;
    preauthorize(hosts: string[]): Promise<void>;
  };
}>({
  extension: async ({}, use) => {
    await promisify(execFile)(
      "mise",
      [
        "exec",
        "--",
        "mix",
        "run",
        "--no-start",
        "priv/repo/extension_e2e_seeds.exs",
      ],
      {
        cwd: resolve("../shroud.email"),
        env: {
          ...process.env,
          MIX_ENV: "test",
          POSTGRES_HOST: "127.0.0.1",
          POSTGRES_DB: "shroud_extension_e2e",
          POSTGRES_PORT: process.env.EXTENSION_E2E_DB_PORT ?? "55437",
          EXTENSION_E2E: "1",
          EXTENSION_E2E_SEED_ONLY: "1",
        },
      },
    );
    const website = await readFile(new URL("./website.html", import.meta.url));
    const server = createServer((req, res) => {
      res.setHeader("Content-Type", "text/html");
      res.end(
        req.url === "/frame"
          ? '<label>Frame email<input type="email"></label>'
          : website,
      );
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    const address = server.address();
    if (!address || typeof address === "string")
      throw new Error("No website port");
    const profile = await mkdtemp(resolve(tmpdir(), "shroud-extension-"));
    const path = resolve(".output/chrome-mv3");
    const context = await chromium.launchPersistentContext(profile, {
      channel: "chromium",
      headless: true,
      args: [`--disable-extensions-except=${path}`, `--load-extension=${path}`],
      viewport: { width: 560, height: 1020 },
    });
    try {
      const worker =
        context.serviceWorkers()[0] ??
        (await context.waitForEvent("serviceworker"));
      const id = new URL(worker.url()).host;
      async function preauthorize(hosts: string[]) {
        const settings = await context.newPage();
        await settings.goto("chrome://extensions/");
        await settings.evaluate(
          async ({ id, hosts }) => {
            const api = (
              globalThis as typeof globalThis & {
                chrome: {
                  developerPrivate: {
                    addHostPermission(id: string, host: string): Promise<void>;
                  };
                };
              }
            ).chrome;
            for (const host of hosts)
              await api.developerPrivate.addHostPermission(id, host);
          },
          { id, hosts },
        );
        await settings.close();
      }
      // Native permission prompts are outside headless Playwright. The real request still activates each grant.
      await preauthorize(["http://localhost/*"]);
      const popup = await context.newPage();
      await popup.goto(`chrome-extension://${id}/popup.html`);
      await use({
        context,
        popup,
        website: `http://127.0.0.1:${address.port}`,
        preauthorize,
      });
    } finally {
      await context.close();
      await rm(profile, { recursive: true, force: true });
      await new Promise<void>((r, reject) =>
        server.close((e) => (e ? reject(e) : r())),
      );
    }
  },
});
export { expect } from "@playwright/test";
