import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { mount, flushPromises, enableAutoUnmount } from "@vue/test-utils";
import App from "../../entrypoints/popup/App.vue";
import type { AccountView, AliasPage } from "../../shared/contracts";

enableAutoUnmount(afterEach);
const transport = vi.hoisted(() => ({ send: vi.fn(), permission: vi.fn() }));
vi.mock("../../shared/contracts", () => ({ request: transport.send }));
vi.mock("wxt/browser", () => ({
  browser: {
    permissions: { request: transport.permission },
    runtime: { onMessage: { addListener() {}, removeListener() {} } },
  },
}));
const account: AccountView = {
  instance: "https://mail.example",
  email: "alex@example.com",
  capabilities: {
    alias_count: 4,
    alias_limit: 5,
    can_create: true,
    default_domain: "fog.shroud.email",
  },
  domains: ["fog.shroud.email", "custom.example"],
  preferences: {
    appearance: "dark",
    showIcon: false,
    selectedDomain: "custom.example",
  },
  websitePermission: false,
};
const alias = {
  address: "created@custom.example",
  enabled: true,
  title: "Shop",
  notes: null,
  forwarded: 0,
  blocked: 0,
  blocked_addresses: [],
};
const page: AliasPage = {
  email_aliases: [alias],
  page_number: 1,
  page_size: 20,
  total_entries: 1,
  total_pages: 1,
};
const copy = vi.fn();
beforeEach(() => {
  vi.clearAllMocks();
  copy.mockResolvedValue(undefined);
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText: copy },
  });
  transport.permission.mockResolvedValue(true);
  transport.send.mockImplementation(async (m) => ({
    ok: true,
    value:
      m.type === "account"
        ? structuredClone(account)
        : m.type === "aliases"
          ? page
          : m.type === "create"
            ? alias
            : undefined,
  }));
});
function button(wrapper: ReturnType<typeof mount>, text: string) {
  const found = wrapper.findAll("button").find((b) => b.text() === text);
  if (!found) throw new Error(`Button not found: ${text}`);
  return found;
}

it("starts with hosted sign-in and a collapsed editable server disclosure", async () => {
  transport.send.mockImplementation(async () => ({ ok: true, value: null }));
  const w = mount(App, { attachTo: document.body });
  await flushPromises();
  expect(w.find('input[type="url"]').exists()).toBe(false);
  await button(w, "Sign in ↗").trigger("click");
  await flushPromises();
  expect(transport.send).toHaveBeenCalledWith({
    type: "login",
    instance: "https://app.shroud.email",
  });
  await button(w, "Server URL ⌄").trigger("click");
  await w.get('input[type="url"]').setValue("https://self.example/");
  await button(w, "Create account ↗").trigger("click");
  await flushPromises();
  expect(transport.send).toHaveBeenCalledWith({
    type: "open",
    destination: "signup",
    instance: "https://self.example",
  });
});

it("creates once with the selected domain and description, and retries only copying on clipboard failure", async () => {
  copy.mockRejectedValueOnce(new Error("Denied"));
  let finish!: (value: unknown) => void;
  transport.send.mockImplementation(async (m) =>
    m.type === "create"
      ? new Promise((resolve) => {
          finish = resolve;
        })
      : {
          ok: true,
          value: m.type === "account" ? structuredClone(account) : page,
        },
  );
  const w = mount(App, { attachTo: document.body });
  await flushPromises();
  await button(w, "+ New alias").trigger("click");
  await w.get('input[aria-label="Description"]').setValue("Receipt & warranty");
  await button(w, "Create & copy alias").trigger("click");
  await button(w, "Creating…").trigger("click");
  finish({ ok: true, value: alias });
  await flushPromises();
  expect(
    transport.send.mock.calls.filter(([m]) => m.type === "create"),
  ).toEqual([
    [
      {
        type: "create",
        input: { domain: "custom.example", title: "Receipt & warranty" },
      },
    ],
  ]);
  expect(w.text()).toContain("created@custom.example");
  await button(w, "Copy").trigger("click");
  await flushPromises();
  expect(copy).toHaveBeenLastCalledWith("created@custom.example");
  expect(
    transport.send.mock.calls.filter(([m]) => m.type === "create"),
  ).toHaveLength(1);
  expect(w.text()).toContain("Alias created and copied");
});

it("keeps custom name and description when another client consumes the last alias", async () => {
  const current = structuredClone(account);
  transport.send.mockImplementation(async (m) => {
    if (m.type === "create") {
      current.capabilities.can_create = false;
      current.capabilities.alias_count = 5;
      return { ok: false, error: { kind: "limit", message: "Limit reached" } };
    }
    return {
      ok: true,
      value:
        m.type === "account"
          ? structuredClone(current)
          : m.type === "aliases"
            ? page
            : undefined,
    };
  });
  const w = mount(App, { attachTo: document.body });
  await flushPromises();
  await button(w, "+ New alias").trigger("click");
  await button(w, "Custom name").trigger("click");
  await w.get('input[aria-label="Custom name"]').setValue("receipt");
  await w.get('input[aria-label="Description"]').setValue("Warranty");
  await button(w, "Create & copy alias").trigger("click");
  await flushPromises();
  expect(w.text()).toContain("Alias limit reached");
  expect(w.get('input[aria-label="Custom name"]').element).toHaveProperty(
    "value",
    "receipt",
  );
  expect(w.get('input[aria-label="Description"]').element).toHaveProperty(
    "value",
    "Warranty",
  );
  expect(button(w, "Create & copy alias").attributes("disabled")).toBeDefined();
});

it("does not replace newer search results with a slower response, including an empty query", async () => {
  const resolvers = new Map<string, (v: unknown) => void>();
  transport.send.mockImplementation((m) =>
    m.type === "aliases"
      ? new Promise((resolve) => resolvers.set(m.search, resolve))
      : Promise.resolve({ ok: true, value: account }),
  );
  const w = mount(App, { attachTo: document.body });
  await flushPromises();
  resolvers.get("")!({ ok: true, value: page });
  await flushPromises();
  await w.get('input[type="search"]').setValue("old");
  await flushPromises();
  await w.get('input[type="search"]').setValue("new");
  await flushPromises();
  resolvers.get("new")!({
    ok: true,
    value: {
      ...page,
      email_aliases: [{ ...alias, address: "new@custom.example" }],
    },
  });
  await flushPromises();
  resolvers.get("old")!({
    ok: true,
    value: {
      ...page,
      email_aliases: [{ ...alias, address: "old@custom.example" }],
    },
  });
  await flushPromises();
  expect(w.find('[data-address="new@custom.example"]').exists()).toBe(true);
  expect(w.find('[data-address="old@custom.example"]').exists()).toBe(false);
  await w.get('input[type="search"]').setValue("");
  await flushPromises();
  resolvers.get("")!({ ok: true, value: page });
  await flushPromises();
  expect(w.find('[data-address="created@custom.example"]').exists()).toBe(true);
});

it("shows the permission action only when missing, and logs out without keeping account data", async () => {
  const current = structuredClone(account);
  transport.send.mockImplementation(async (m) => ({
    ok: true,
    value:
      m.type === "account" ? current : m.type === "aliases" ? page : undefined,
  }));
  const w = mount(App, { attachTo: document.body });
  await flushPromises();
  await w.get('button[aria-label="Settings"]').trigger("click");
  expect(w.find('[role="switch"]').attributes("aria-checked")).toBe("false");
  expect(button(w, "Allow website access").exists()).toBe(true);
  current.websitePermission = true;
  await button(w, "Allow website access").trigger("click");
  await flushPromises();
  expect(w.text()).not.toContain("Allow website access");
  await button(w, "Logout").trigger("click");
  await flushPromises();
  expect(w.text()).not.toContain("alex@example.com");
  expect(w.text()).toContain("Sign in");
});
