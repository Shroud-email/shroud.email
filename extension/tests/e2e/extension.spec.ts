import { test, expect } from "./fixtures";
import type { BrowserContext, Page } from "@playwright/test";
async function signIn(
  context: BrowserContext,
  popup: Page,
  name: "free" | "paid",
  allow = true,
) {
  await popup.getByRole("button", { name: /Server URL/ }).click();
  await popup
    .getByRole("textbox", { name: "Server URL" })
    .fill("http://localhost:4407");
  const opened = context.waitForEvent("page", { timeout: 20_000 });
  await popup.getByRole("button", { name: "Sign in ↗" }).click();
  const login = await opened;
  const email = login.locator("#login-form input[type=email]");
  await expect(
    email.or(login.getByRole("button", { name: "Connect", exact: true })),
  ).toBeVisible();
  if (await email.isVisible()) {
    await email.fill(`extension-${name}@example.test`);
    await login
      .locator("#login-form input[type=password]")
      .fill("extension test passphrase");
    await login.getByRole("button", { name: "Sign in", exact: true }).click();
  }
  await login
    .getByRole("button", { name: allow ? "Connect" : "Cancel", exact: true })
    .click();
  if (allow)
    await expect(
      popup.getByRole("heading", { name: "Aliases", exact: true }),
    ).toBeVisible();
  else
    await expect(
      popup.getByRole("button", { name: "Sign in ↗" }),
    ).toBeEnabled();
}
test("OAuth, custom-domain creation, search, fill identity, permissions and logout", async ({
  extension,
}) => {
  const { context, popup, website } = extension;
  await signIn(context, popup, "paid");
  await popup.getByRole("button", { name: "Next", exact: true }).click();
  await expect(popup.getByText("2 / 2", { exact: true })).toBeVisible();
  await popup
    .getByRole("searchbox", { name: "Search aliases" })
    .fill("paid-1@");
  await expect(popup.locator("[data-address]")).toHaveCount(1);
  await popup.getByRole("searchbox", { name: "Search aliases" }).fill("");
  const devtools = await context.newCDPSession(popup);
  const { targetInfos } = await devtools.send("Target.getTargets");
  const worker = targetInfos.find(
    (t) =>
      t.type === "service_worker" &&
      new URL(t.url).host === new URL(popup.url()).host,
  );
  expect(worker).toBeDefined();
  await devtools.send("Target.closeTarget", { targetId: worker!.targetId });
  await popup.reload();
  await expect(popup.locator("[data-address]")).toHaveCount(20);
  await popup.getByRole("button", { name: "Settings", exact: true }).click();
  await popup.getByRole("button", { name: "Dark", exact: true }).click();
  await extension.preauthorize(["http://*/*", "https://*/*"]);
  await popup.getByRole("button", { name: "Allow website access" }).click();
  await expect(
    popup.getByRole("button", { name: "Allow website access" }),
  ).toHaveCount(0);
  await popup
    .getByRole("switch", { name: "Show icon in email fields" })
    .click();
  const site = await context.newPage();
  await site.goto(website);
  await expect(
    site.getByRole("button", { name: "Use a Shroud.email alias" }),
  ).toHaveCount(2);
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .first()
    .click();
  await expect(
    site.getByRole("button", { name: "+ Create & fill", exact: true }),
  ).toBeEnabled();
  const siteTools = await context.newCDPSession(site);
  await siteTools.send("DOM.enable");
  await siteTools.send("CSS.enable");
  const { root } = await siteTools.send("DOM.getDocument", {
    depth: -1,
    pierce: true,
  });
  const { nodeId: hostId } = await siteTools.send("DOM.querySelector", {
    nodeId: root.nodeId,
    selector: "[data-shroud-owned]",
  });
  const { node: hostNode } = await siteTools.send("DOM.describeNode", {
    nodeId: hostId,
  });
  const { nodeId: titleId } = await siteTools.send("DOM.querySelector", {
    nodeId: hostNode.shadowRoots![0]!.nodeId,
    selector: "strong",
  });
  const { fonts } = await siteTools.send("CSS.getPlatformFontsForNode", {
    nodeId: titleId,
  });
  expect(
    fonts.some((font) => font.isCustomFont && font.familyName === "Inter"),
  ).toBe(true);
  await site.screenshot({
    path: "../.amp/in/artifacts/inline-default-dark.png",
  });
  await site.getByRole("button", { name: "Domain", exact: true }).click();
  await site.screenshot({
    path: "../.amp/in/artifacts/inline-dropdown-dark.png",
  });
  await site.getByRole("option", { name: /custom.example.test/ }).click();
  await expect(
    site.getByRole("button", { name: "Domain", exact: true }),
  ).toHaveText(/custom.example.test/);
  await site.screenshot({
    path: "../.amp/in/artifacts/inline-custom-dark.png",
  });
  await site
    .getByRole("button", { name: "+ Create & fill", exact: true })
    .click();
  await expect(site.getByLabel("Work email")).toHaveValue(
    /^[^@]+@custom\.example\.test$/,
  );
  const created = await site.getByLabel("Work email").inputValue();
  await expect(site.getByLabel("Backup email")).toHaveValue("");
  await expect(site.locator("#input-count")).toHaveText("1");
  await expect(site.locator("#change-count")).toHaveText("1");
  await expect(site.locator("#submit-count")).toHaveText("0");
  await popup.getByRole("button", { name: "‹ Settings" }).click();
  await popup.getByRole("searchbox", { name: "Search aliases" }).fill(created);
  await expect(popup.locator("[data-address]")).toHaveCount(1);
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .nth(1)
    .click();
  await site.getByRole("button", { name: "Browse all aliases ↗" }).click();
  await site.getByRole("searchbox", { name: "Search aliases" }).fill(created);
  await expect(site.locator("[data-address]")).toHaveCount(1);
  await site.getByRole("button", { name: "Fill email →" }).click();
  await expect(site.getByLabel("Backup email")).toHaveValue(created);
  await expect(site.locator("#submit-count")).toHaveText("0");
  const frame = site.frameLocator("iframe");
  await frame.getByRole("button", { name: "Use a Shroud.email alias" }).click();
  await frame.getByRole("button", { name: "Fill email →" }).first().click();
  await expect(frame.getByLabel("Frame email")).toHaveValue(created);
  await expect(site.getByLabel("Work email")).toHaveValue(created);
  await site.getByRole("button", { name: "Add email field" }).click();
  await expect(
    site.getByRole("button", { name: "Use a Shroud.email alias" }),
  ).toHaveCount(3);
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .last()
    .click();
  await site.keyboard.press("Escape");
  await expect(site.getByLabel("Dynamic email")).toBeFocused();
  await site.setViewportSize({ width: 320, height: 760 });
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .first()
    .click();
  await expect(
    site.getByRole("button", { name: "+ Create & fill", exact: true }),
  ).toBeVisible();
  const bounds = await site.locator(".inline-container").boundingBox();
  expect(bounds!.x).toBeGreaterThanOrEqual(8);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(312);
  await site.screenshot({
    path: "../.amp/in/artifacts/inline-narrow-dark.png",
  });
  await site.getByRole("heading", { name: "Create your account" }).click();
  await expect(site.locator(".inline-container")).toHaveCount(0);
  await popup.getByRole("button", { name: "Settings", exact: true }).click();
  await popup.evaluate(async () => {
    const api = (
      globalThis as typeof globalThis & {
        chrome: typeof import("wxt/browser").browser;
      }
    ).chrome;
    await api.permissions.remove({ origins: ["https://*/*", "http://*/*"] });
  });
  await expect(
    site.getByRole("button", { name: "Use a Shroud.email alias" }),
  ).toHaveCount(0);
  await popup.getByRole("button", { name: "Logout", exact: true }).click();
  await expect(popup.getByRole("button", { name: "Sign in ↗" })).toBeVisible();
});
test("free capacity includes disabled aliases and remains usable at the limit", async ({
  extension,
}) => {
  const { context, popup } = extension;
  await signIn(context, popup, "free");
  await popup.getByRole("button", { name: "Settings", exact: true }).click();
  await popup.getByRole("button", { name: "Dark", exact: true }).click();
  await popup.getByRole("button", { name: "‹ Settings" }).click();
  for (let i = 0; i < 3; i++) {
    await popup.getByRole("button", { name: "+ New alias" }).click();
    await popup.getByRole("button", { name: "Create & copy alias" }).click();
    await expect(
      popup.getByRole("heading", { name: "Aliases", exact: true }),
    ).toBeVisible();
  }
  await expect(
    popup.getByText("Alias limit reached", { exact: true }),
  ).toBeVisible();
  await expect(
    popup.getByRole("button", { name: "+ New alias" }),
  ).toBeDisabled();
  await popup.screenshot({
    path: "../.amp/in/artifacts/limit-integration-dark.png",
  });
  await popup
    .getByRole("searchbox", { name: "Search aliases" })
    .fill("free-1@");
  await expect(popup.locator("[data-address]")).toHaveCount(1);
  await popup.getByRole("button", { name: "Settings", exact: true }).click();
  await extension.preauthorize(["http://*/*", "https://*/*"]);
  await popup.getByRole("button", { name: "Allow website access" }).click();
  await popup
    .getByRole("switch", { name: "Show icon in email fields" })
    .click();
  const site = await context.newPage();
  await site.goto(extension.website);
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .first()
    .click();
  await expect(
    site.getByRole("button", { name: "+ Create & fill", exact: true }),
  ).toBeDisabled();
  await site.screenshot({ path: "../.amp/in/artifacts/inline-limit-dark.png" });
  await site.getByRole("button", { name: "Fill email →" }).first().click();
  await expect(site.getByLabel("Work email")).toHaveValue(
    /@fog\.shroud\.test$/,
  );
});
test("cancelled consent and a replaced input retain a single created alias for Copy", async ({
  extension,
}) => {
  const { context, popup } = extension;
  await signIn(context, popup, "paid", false);
  await popup.reload();
  await signIn(context, popup, "paid");
  await popup.getByRole("button", { name: "Settings", exact: true }).click();
  await extension.preauthorize(["http://*/*", "https://*/*"]);
  await popup.getByRole("button", { name: "Allow website access" }).click();
  await popup
    .getByRole("switch", { name: "Show icon in email fields" })
    .click();
  const site = await context.newPage();
  await site.goto(extension.website);
  await site
    .getByRole("button", { name: "Use a Shroud.email alias" })
    .first()
    .click();
  await expect(
    site.getByRole("button", { name: "+ Create & fill", exact: true }),
  ).toBeEnabled();
  await site.screenshot({ path: "../.amp/in/artifacts/inline-default-light.png" });
  let started!: () => void;
  const sent = new Promise<void>((r) => {
    started = r;
  });
  let release!: () => void;
  const gate = new Promise<void>((r) => {
    release = r;
  });
  let posts = 0;
  await context.route("**/api/v1/aliases", async (route) => {
    if (route.request().method() === "POST") {
      posts++;
      started();
      await gate;
    }
    await route.continue();
  });
  await site
    .getByRole("button", { name: "+ Create & fill", exact: true })
    .click();
  await sent;
  await site.evaluate(() => {
    const input = document.querySelector("#work")!;
    input.replaceWith(input.cloneNode());
  });
  release();
  await expect(
    site.getByRole("button", { name: "Copy", exact: true }),
  ).toBeVisible();
  await site.screenshot({ path: "../.amp/in/artifacts/inline-copy-light.png" });
  await expect(site.getByLabel("Work email")).toHaveValue("");
  await context.grantPermissions(["clipboard-read"], {
    origin: extension.website,
  });
  await site.getByRole("button", { name: "Copy", exact: true }).click();
  const copied = await site.evaluate(() => navigator.clipboard.readText());
  expect(copied).toMatch(/^[^@]+@fog\.shroud\.test$/);
  expect(posts).toBe(1);
  await popup.getByRole("button", { name: "‹ Settings" }).click();
  await popup.getByRole("searchbox", { name: "Search aliases" }).fill(copied);
  await expect(popup.locator("[data-address]")).toHaveCount(1);
});
