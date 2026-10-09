import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { discoverFields, fillField, observeFields } from "../../content/fields";

beforeEach(() => {
  document.body.innerHTML = "";
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
});
afterEach(() => vi.restoreAllMocks());
it("discovers editable email fields, including dynamic inputs, but not hidden fields or other frames", async () => {
  document.body.innerHTML =
    '<input type="email" id="first"><input type="email" disabled><input type="email" readonly><div hidden><input type="email"></div><div style="display:none"><input type="email"></div><input type="text"><iframe></iframe>';
  document.querySelector("iframe")!.contentDocument!.body.innerHTML =
    '<input type="email">';
  expect(discoverFields(document).map((f) => f.id)).toEqual(["first"]);
  let found: HTMLInputElement[] = [];
  const stop = observeFields(document, (fields) => {
    found = fields;
  });
  const next = document.createElement("input");
  next.type = "email";
  next.id = "dynamic";
  document.body.append(next);
  await Promise.resolve();
  await Promise.resolve();
  expect(found.map((f) => f.id)).toEqual(["first", "dynamic"]);
  next.readOnly = true;
  await Promise.resolve();
  await Promise.resolve();
  expect(found.map((f) => f.id)).toEqual(["first"]);
  stop();
  next.readOnly = false;
  await Promise.resolve();
  await Promise.resolve();
  expect(found.map((f) => f.id)).toEqual(["first"]);
});
it("uses the native setter and emits both website events, without submitting the form", () => {
  document.body.innerHTML = '<form><input type="email"></form>';
  const field = document.querySelector("input")!;
  const native = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype,
    "value",
  )!;
  Object.defineProperty(field, "value", {
    get() {
      return native.get!.call(this);
    },
    set() {
      native.set!.call(this, "wrong");
    },
  });
  const observed: string[] = [];
  document
    .querySelector("form")!
    .addEventListener("input", () => observed.push(`input:${field.value}`));
  document
    .querySelector("form")!
    .addEventListener("change", () => observed.push(`change:${field.value}`));
  document
    .querySelector("form")!
    .addEventListener("submit", () => observed.push("submit"));
  expect(fillField(field, "chosen@custom.example")).toBe(true);
  expect(observed).toEqual([
    "input:chosen@custom.example",
    "change:chosen@custom.example",
  ]);
});
it("never fills a replacement, detached, or newly read-only input", () => {
  const original = document.createElement("input");
  original.type = "email";
  document.body.append(original);
  const replacement = original.cloneNode() as HTMLInputElement;
  original.replaceWith(replacement);
  expect(fillField(original, "kept@domain.example")).toBe(false);
  expect(replacement.value).toBe("");
  replacement.readOnly = true;
  expect(fillField(replacement, "kept@domain.example")).toBe(false);
});
