import assert from "node:assert/strict";
import test from "node:test";

import { setupPaddleCheckout } from "./paddle_checkout.mjs";

function fixture({ token = "test_token", checkout = true } = {}) {
  const listeners = {};
  const button = {
    dataset: checkout
      ? { paddleCheckout: "true", paddleCheckoutUrl: "/checkout/paddle" }
      : {},
    disabled: true,
    textContent: "Upgrade",
    title: "",
    closest(selector) {
      return selector.includes("upgrade-button") ? this : null;
    },
  };
  const meta = {
    "meta[name='paddle-client-token']": { content: token },
    "meta[name='paddle-environment']": { content: "sandbox" },
    "meta[name='csrf-token']": { content: "csrf-token" },
  };
  const document = {
    querySelector(selector) {
      if (selector === "#upgrade-button") return button;
      return meta[selector] ?? null;
    },
    addEventListener(name, listener) {
      listeners[name] = listener;
    },
  };

  return { button, document, listeners };
}

test("an early checkout request waits for Paddle initialization", async () => {
  const { button, document, listeners } = fixture();
  let resolvePaddle;
  const opened = [];
  const paddle = { Checkout: { open: (options) => opened.push(options) } };
  const initializePaddle = () =>
    new Promise((resolve) => {
      resolvePaddle = resolve;
    });
  const window = {
    fetch: async () => ({ ok: true, json: async () => ({ transaction_id: "txn_123" }) }),
    location: { href: "" },
  };

  setupPaddleCheckout({ document, window, initializePaddle });
  const click = listeners.click({ target: button });

  assert.equal(button.disabled, true);
  assert.deepEqual(opened, []);

  resolvePaddle(paddle);
  await click;

  assert.deepEqual(opened, [
    {
      transactionId: "txn_123",
      settings: { displayMode: "overlay", theme: "light", locale: "en" },
    },
  ]);
});

test("missing configuration leaves checkout unavailable", async () => {
  const { button, document } = fixture({ token: "", checkout: false });
  let initialized = false;

  await setupPaddleCheckout({
    document,
    window: {},
    initializePaddle: () => {
      initialized = true;
    },
  });

  assert.equal(initialized, false);
  assert.equal(button.disabled, true);
});

test("failed initialization leaves visible unavailable state", async () => {
  const { button, document } = fixture();

  await setupPaddleCheckout({
    document,
    window: {},
    initializePaddle: async () => {
      throw new Error("network failed");
    },
    logger: { error() {} },
  });

  assert.equal(button.disabled, true);
  assert.equal(button.textContent, "Payments unavailable");
  assert.match(button.title, /couldn't load/i);
});
