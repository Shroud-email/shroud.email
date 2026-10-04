import assert from "node:assert/strict";
import test from "node:test";
import {
  LiveToast,
  NotificationSource,
  initializeFlashNotifications,
} from "./notifications.mjs";
import { createLiveToastHook } from "../vendor/live_toast.ts";

test("controller flashes get status semantics and local dismissal, LiveViews keep their own handler", (context) => {
  const listeners = {};
  function flash(kind, live) {
    const attributes = {};
    const buttonAttributes = {};
    const element = {
      dataset: { kind },
      style: {},
      setAttribute(key, value) {
        attributes[key] = value;
      },
      closest() {
        return live ? {} : null;
      },
      querySelector() {
        return button;
      },
      remove() {
        this.removed = true;
      },
    };
    const button = {
      setAttribute(key, value) {
        buttonAttributes[key] = value;
      },
      closest(selector) {
        return selector === "[data-phx-main]" ? element.closest() : element;
      },
    };
    return { element, button, attributes, buttonAttributes };
  }
  const info = flash("info", false);
  const error = flash("error", false);
  const live = flash("success", true);
  const previousWindow = globalThis.window;
  const previousDocument = globalThis.document;
  context.after(() => {
    if (previousWindow === undefined) delete globalThis.window;
    else globalThis.window = previousWindow;
    if (previousDocument === undefined) delete globalThis.document;
    else globalThis.document = previousDocument;
  });
  globalThis.window = { matchMedia: () => ({ matches: false }) };
  globalThis.document = {
    querySelectorAll: () => [info.element, error.element, live.element],
    addEventListener: (name, listener) => {
      listeners[name] = listener;
    },
  };

  initializeFlashNotifications();
  assert.equal(info.attributes.role, "status");
  assert.equal(error.attributes.role, "alert");
  assert.equal(info.attributes["aria-atomic"], "true");
  assert.equal(info.buttonAttributes["aria-label"], "Dismiss notification");
  assert.equal(info.element.dataset.corner, "bottom_center");
  assert.equal(info.element.style.opacity, "1");
  assert.equal(live.element.style.opacity, undefined);

  listeners.click({ target: { closest: () => info.button } });
  assert.equal(info.element.removed, true);
  assert.equal(error.element.removed, undefined);
  listeners.click({ target: { closest: () => live.button } });
  assert.equal(live.element.removed, undefined);
  listeners.click({ target: { closest: () => null } });
});

function liveFixture(context, template) {
  const originals = Object.fromEntries(
    ["window", "document", "ResizeObserver"].map((key) => [
      key,
      globalThis[key],
    ]),
  );
  const media = new EventTarget();
  media.matches = true;
  const win = new EventTarget();
  Object.assign(win, {
    matchMedia: () => media,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
  });
  globalThis.window = win;
  globalThis.ResizeObserver = class {
    constructor(callback) {
      this.callback = callback;
    }
    observe() {}
    disconnect() {
      this.disconnected = true;
    }
  };
  const toasts = [];
  const groupElement = new EventTarget();
  Object.assign(groupElement, {
    dataset: { liveToastGroup: "true" },
    querySelectorAll: () => toasts,
  });
  globalThis.document = {
    getElementById: (id) => (id === "toast-group" ? groupElement : null),
    querySelectorAll: () => toasts,
  };
  const pushes = [];
  const animate = (element, keyframes) => {
    element.lastAnimation = keyframes;
    element.animationCount = (element.animationCount || 0) + 1;
    return { finished: Promise.resolve() };
  };
  function mount(element) {
    const hook = template
      ? { ...template, animateToast: animate }
      : createLiveToastHook(8000, 3, animate);
    Object.assign(hook, {
      el: element,
      handleEvent(name, callback) {
        const listener = (event) => callback(event.detail);
        win.addEventListener(`phx:${name}`, listener);
        return { name, listener };
      },
      removeHandleEvent({ name, listener }) {
        win.removeEventListener(`phx:${name}`, listener);
      },
      pushEvent(name, payload) {
        pushes.push({ element, name, payload });
      },
      pushEventTo(target, name, payload) {
        pushes.push({ element, target, name, payload });
      },
    });
    hook.mounted();
    return hook;
  }
  const group = mount(groupElement);
  function toast(id, height) {
    const element = new EventTarget();
    Object.assign(element, {
      id,
      dataset: { kind: "info", duration: "0", corner: "top_right" },
      offsetHeight: height,
      offsetParent: {},
      isConnected: true,
      style: {},
      classList: { add() {}, remove() {} },
      closest: () => ({ parentElement: groupElement }),
    });
    toasts.push(element);
    return mount(element);
  }
  function destroy(hook) {
    if (hook.active === false) return;
    const index = toasts.indexOf(hook.el);
    if (index !== -1) toasts.splice(index, 1);
    hook.el.isConnected = false;
    hook.destroyed();
  }
  context.after(() => {
    destroy(group);
    for (const [key, value] of Object.entries(originals)) {
      if (value === undefined) delete globalThis[key];
      else globalThis[key] = value;
    }
  });
  return { media, win, group, toasts, pushes, toast, destroy };
}

test("one group acknowledges flashes after repeated toast destruction and none after navigation", (context) => {
  const fixture = liveFixture(context);
  for (let n = 0; n < 10; n++) {
    const toast = fixture.toast(`toast-${n}`, 60);
    fixture.destroy(toast);
    assert.equal(toast.resizeObserver.disconnected, true);
  }
  const active = fixture.toast("toast-active", 60);
  fixture.win.dispatchEvent(
    new CustomEvent("phx:clear-flash", { detail: { key: "info" } }),
  );
  assert.deepEqual(
    fixture.pushes.map(({ name, payload }) => ({ name, payload })),
    [{ name: "lv:clear-flash", payload: { key: "info" } }],
  );
  fixture.destroy(active);
  fixture.destroy(fixture.group);
  fixture.win.dispatchEvent(
    new CustomEvent("phx:clear-flash", { detail: { key: "error" } }),
  );
  fixture.win.dispatchEvent(
    new CustomEvent("phx:live-toast-dismiss", {
      detail: { id: "toast-active" },
    }),
  );
  assert.equal(fixture.pushes.length, 1);
  assert.equal(fixture.group.resizeObserver.disconnected, true);
});

test("stack offsets use current asymmetric heights on resize and stay correct after mobile DOM patches", (context) => {
  const fixture = liveFixture(context);
  const first = fixture.toast("toast-first", 37);
  const second = fixture.toast("toast-second", 83);
  const third = fixture.toast("toast-third", 52);
  assert.equal(first.el.targetDestination, "165px");
  assert.equal(second.el.targetDestination, "67px");

  first.el.offsetHeight = 75;
  second.el.offsetHeight = 131;
  third.el.offsetHeight = 96;
  fixture.media.matches = false;
  fixture.media.dispatchEvent(new Event("change"));
  assert.equal(first.el.targetDestination, "-257px");
  assert.equal(second.el.targetDestination, "-111px");

  // A further width/font change stays inside the mobile breakpoint.
  third.el.offsetHeight = 140;
  third.resizeObserver.callback();
  assert.equal(first.el.targetDestination, "-301px");
  assert.equal(second.el.targetDestination, "-155px");

  first.el.dataset.corner = "top_right";
  first.updated();
  first.updated();
  assert.equal(first.el.dataset.corner, "bottom_center");
  assert.equal(first.el.targetDestination, "-301px");
  assert.equal(first.el.lastAnimation.transform.at(-1), "translateY(-301px)");
});

test("unchanged layouts do not restart animation or reorder existing notifications", (context) => {
  const fixture = liveFixture(context);
  const created = fixture.toast("created", 81);
  const disabled = fixture.toast("disabled", 49);
  const enabled = fixture.toast("enabled", 67);
  assert.equal(created.el.targetDestination, "146px");
  assert.equal(disabled.el.targetDestination, "82px");
  assert.equal(enabled.el.targetDestination, "0px");
  const counts = [created, disabled, enabled].map(
    (hook) => hook.el.animationCount,
  );
  for (let n = 0; n < 10; n++) {
    fixture.group.layout();
    created.updated();
  }
  assert.deepEqual(
    [created, disabled, enabled].map((hook) => hook.el.animationCount),
    counts,
  );
});

test("page sources queue before the persistent group mounts and forward each ID only once", (context) => {
  let messages = [
    {
      dataset: { id: "created", kind: "success", duration: "8000" },
      textContent: "Created alias.",
    },
  ];
  const acknowledgements = [];
  const source = {
    ...NotificationSource,
    el: { querySelectorAll: () => messages },
    pushEvent: (name, payload) => acknowledgements.push({ name, payload }),
  };
  source.mounted();
  source.updated();
  const fixture = liveFixture(context, LiveToast);
  assert.equal(fixture.pushes.length, 1);
  assert.deepEqual(fixture.pushes[0].payload, {
    kind: "success",
    message: "Created alias.",
    options: { duration: 8000 },
  });
  messages = [
    {
      dataset: { id: "enabled-1", kind: "info", duration: "8000" },
      textContent: "Enabled alias.",
    },
  ];
  source.updated();
  source.updated();
  messages = [
    {
      dataset: { id: "enabled-2", kind: "info", duration: "8000" },
      textContent: "Enabled alias.",
    },
  ];
  source.updated();
  // A new page's source shares the same surviving sink, including persistent errors.
  messages = [
    {
      dataset: { id: "error", kind: "error", duration: "0" },
      textContent: "Failed.",
    },
  ];
  const nextPage = { ...source, ...NotificationSource };
  nextPage.mounted();
  assert.deepEqual(
    fixture.pushes.map(({ payload }) => payload.message),
    ["Created alias.", "Enabled alias.", "Enabled alias.", "Failed."],
  );
  assert.equal(fixture.pushes.at(-1).payload.options.duration, 0);
  assert.equal(acknowledgements.length, 4);
});

test("overflow removal timers are not duplicated by reflows and are cancelled on navigation", (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const fixture = liveFixture(context);
  for (let n = 0; n < 5; n++) fixture.toast(`toast-${n}`, 40 + n * 10);
  for (let n = 0; n < 10; n++) fixture.group.layout();
  assert.equal(fixture.group.overflowTimers.size, 2);
  context.mock.timers.tick(8005);
  assert.deepEqual(fixture.pushes.map(({ payload }) => payload.id).sort(), [
    "toast-0",
    "toast-1",
  ]);

  fixture.group.layout();
  fixture.destroy(fixture.group);
  context.mock.timers.tick(8005);
  assert.equal(fixture.pushes.length, 2);
});
