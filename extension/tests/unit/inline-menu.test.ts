import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils";
import InlineMenu from "../../content/InlineMenu.vue";
import type { AccountView } from "../../shared/contracts";
enableAutoUnmount(afterEach);
const send = vi.hoisted(() => vi.fn());
vi.mock("../../shared/contracts", () => ({ request: send }));
let field: HTMLInputElement;
let account: AccountView;
const aliases = [
  "a@other.example",
  "b@fog.shroud.email",
  "c@other.example",
].map((address) => ({
  address,
  enabled: true,
  title: "Account-wide",
  notes: null,
  forwarded: 0,
  blocked: 0,
  blocked_addresses: [],
}));
beforeEach(() => {
  vi.clearAllMocks();
  field = document.createElement("input");
  field.type = "email";
  document.body.append(field);
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue({
    x: 0,
    y: 0,
    left: 0,
    top: 0,
    right: 240,
    bottom: 44,
    width: 240,
    height: 44,
    toJSON() {},
  });
  account = {
    instance: "https://mail.example",
    email: "alex@example.com",
    domains: ["fog.shroud.email", "custom.example"],
    capabilities: {
      alias_count: 4,
      alias_limit: 5,
      can_create: true,
      default_domain: "fog.shroud.email",
    },
    preferences: {
      appearance: "dark",
      showIcon: true,
      selectedDomain: "custom.example",
    },
    websitePermission: true,
  };
  send.mockImplementation(async (m) => ({
    ok: true,
    value:
      m.type === "account"
        ? structuredClone(account)
        : m.type === "aliases"
          ? {
              email_aliases: aliases,
              page_number: 1,
              page_size: 3,
              total_pages: 1,
              total_entries: 3,
            }
          : m.type === "create"
            ? { ...aliases[0], address: "created@custom.example" }
            : undefined,
  }));
});
afterEach(() => {
  field.remove();
  vi.restoreAllMocks();
});
it("keeps recent aliases account-wide, remembers domain for creation, and fills without creating", async () => {
  const w = mount(InlineMenu, {
    props: { target: field },
    attachTo: document.body,
  });
  await flushPromises();
  expect(w.text()).toContain("a@other.example");
  expect(w.text()).toContain("b@fog.shroud.email");
  expect(
    w.findAll("button").filter((b) => b.text() === "Fill email →"),
  ).toHaveLength(3);
  await w.get('button[aria-label="Domain"]').trigger("click");
  await w
    .get('[role="option"][data-domain="fog.shroud.email"]')
    .trigger("click");
  await flushPromises();
  expect(send).toHaveBeenCalledWith({
    type: "selected-domain",
    domain: "fog.shroud.email",
  });
  await w
    .findAll("button")
    .find((b) => b.text() === "Fill email →")!
    .trigger("click");
  expect(field.value).toBe("a@other.example");
  expect(send.mock.calls.filter(([m]) => m.type === "create")).toHaveLength(0);
});
it("retains the created address if the original input is replaced during creation", async () => {
  let complete!: (v: unknown) => void;
  send.mockImplementation(async (m) =>
    m.type === "create"
      ? new Promise((r) => {
          complete = r;
        })
      : {
          ok: true,
          value:
            m.type === "account"
              ? structuredClone(account)
              : { email_aliases: aliases },
        },
  );
  const w = mount(InlineMenu, {
    props: { target: field },
    attachTo: document.body,
  });
  await flushPromises();
  const create = w
    .findAll("button")
    .find((b) => b.text() === "+ Create & fill")!;
  await create.trigger("click");
  await create.trigger("click");
  const replacement = field.cloneNode() as HTMLInputElement;
  field.replaceWith(replacement);
  complete({
    ok: true,
    value: { ...aliases[0], address: "kept@custom.example" },
  });
  await flushPromises();
  expect(replacement.value).toBe("");
  expect(w.text()).toContain("kept@custom.example");
  expect(w.findAll("button").some((b) => b.text() === "Copy")).toBe(true);
  expect(send.mock.calls.filter(([m]) => m.type === "create")).toHaveLength(1);
  replacement.remove();
});
it("hides domain selection for a single domain, and leaves fill/browse usable at the limit", async () => {
  account.domains = ["fog.shroud.email"];
  account.capabilities.can_create = false;
  account.capabilities.alias_count = 5;
  const w = mount(InlineMenu, {
    props: { target: field },
    attachTo: document.body,
  });
  await flushPromises();
  expect(w.find('button[aria-label="Domain"]').exists()).toBe(false);
  expect(w.text()).toContain("Alias limit reached");
  expect(
    w
      .findAll("button")
      .find((b) => b.text() === "+ Create & fill")!
      .attributes("disabled"),
  ).toBeDefined();
  await w
    .findAll("button")
    .find((b) => b.text() === "Browse all aliases ↗")!
    .trigger("click");
  await flushPromises();
  expect(w.find('input[type="search"]').exists()).toBe(true);
  await w
    .findAll("button")
    .find((b) => b.text() === "Fill email →")!
    .trigger("click");
  expect(field.value).toBe("a@other.example");
});
it("cannot create on the previous domain while a selection is being saved", async () => {
  const originalSend = send.getMockImplementation()!;
  let finish!: (value: unknown) => void;
  send.mockImplementation((m) =>
    m.type === "selected-domain"
      ? new Promise((r) => {
          finish = r;
        })
      : originalSend(m),
  );
  const w = mount(InlineMenu, {
    props: { target: field },
    attachTo: document.body,
  });
  await flushPromises();
  await w.get('button[aria-label="Domain"]').trigger("click");
  await w.get('[data-domain="fog.shroud.email"]').trigger("click");
  const create = w
    .findAll("button")
    .find((b) => b.text() === "+ Create & fill")!;
  expect(create.attributes("disabled")).toBeDefined();
  finish({ ok: true });
  await flushPromises();
  await create.trigger("click");
  await flushPromises();
  expect(send).toHaveBeenCalledWith({
    type: "create",
    input: { domain: "fog.shroud.email" },
  });
});
