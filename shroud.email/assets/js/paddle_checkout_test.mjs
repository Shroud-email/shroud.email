import assert from "node:assert/strict";
import test from "node:test";

import { setupPaddleCheckout } from "./paddle_checkout.mjs";

function fixture({ token = "test_token", checkout = true, priceId } = {}) {
  const listeners = {};
  const priceAmount = { textContent: "—" };
  const priceCurrency = { textContent: "Loading price…" };
  const price = {
    dataset: { paddlePriceId: priceId },
    querySelector(selector) {
      if (selector === "#upgrade-price-amount") return priceAmount;
      if (selector === "#upgrade-price-currency") return priceCurrency;
      return null;
    },
  };
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
      if (selector === "#upgrade-price[data-paddle-price-id]") {
        return priceId ? price : null;
      }
      return meta[selector] ?? null;
    },
    addEventListener(name, listener) {
      listeners[name] = listener;
    },
    removeEventListener(name, listener) {
      if (listeners[name] === listener) delete listeners[name];
    },
  };

  return { button, document, listeners, priceAmount, priceCurrency };
}

function pricePreview({ priceId, total, currencyCode }) {
  const totals = { subtotal: "2500", discount: "0", tax: "0", total: "2500" };
  const formattedTotals = {
    subtotal: total,
    discount: "£0.00",
    tax: "£0.00",
    total,
  };

  return {
    data: {
      customerId: null,
      addressId: null,
      businessId: null,
      currencyCode,
      address: { countryCode: "GB", postalCode: null },
      customerIpAddress: "192.0.2.1",
      discountId: null,
      details: {
        lineItems: [
          {
            price: {
              id: priceId,
              productId: "pro_yearly",
              name: "Pro yearly",
              description: "Shroud Pro billed yearly",
              billingCycle: { interval: "year", frequency: 1 },
              trialPeriod: null,
              taxMode: "account_setting",
              unitPrice: { amount: "2500", currencyCode },
              unitPriceOverrides: [],
              quantity: { minimum: 1, maximum: 1 },
              status: "active",
              customData: null,
              importMeta: null,
            },
            quantity: 1,
            taxRate: "0",
            unitTotals: totals,
            formattedUnitTotals: formattedTotals,
            totals,
            formattedTotals,
            product: {
              id: "pro_yearly",
              name: "Shroud Pro",
              description: null,
              taxCategory: "saas",
              imageUrl: null,
              customData: null,
              status: "active",
              createdAt: "2026-08-28T00:00:00Z",
              importMeta: null,
            },
            discounts: [],
          },
        ],
      },
      availablePaymentMethods: ["card"],
    },
    meta: { requestId: "req_123" },
  };
}

test("displays Paddle's localized total for the configured yearly price", async () => {
  const priceId = "pri_test_yearly";
  const { document, priceAmount, priceCurrency } = fixture({ priceId });
  let previewParams;
  const paddle = {
    Checkout: { open() {} },
    PricePreview: async (params) => {
      previewParams = params;
      return pricePreview({ priceId, total: "£25.00", currencyCode: "GBP" });
    },
  };

  await setupPaddleCheckout({
    document,
    window: {},
    initializePaddle: async () => paddle,
  });
  await Promise.resolve();

  assert.deepEqual(previewParams, { items: [{ priceId, quantity: 1 }] });
  assert.equal(priceAmount.textContent, "£25.00");
  assert.equal(priceCurrency.textContent, "GBP");
});

test("falls back to checkout pricing when Paddle price preview fails", async () => {
  const { button, document, priceAmount, priceCurrency } = fixture({
    priceId: "pri_test_yearly",
  });
  const paddle = {
    Checkout: { open() {} },
    PricePreview: async () => {
      throw new Error("preview unavailable");
    },
  };

  await setupPaddleCheckout({
    document,
    window: {},
    initializePaddle: async () => paddle,
    logger: { error() {} },
  });
  await Promise.resolve();

  assert.equal(priceAmount.textContent, "—");
  assert.equal(priceCurrency.textContent, "Price shown at checkout");
  assert.equal(button.disabled, false);
});

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
    fetch: async () => ({
      ok: true,
      json: async () => ({
        transaction_id: "txn_123",
        customer: { email: "account@example.com" },
      }),
    }),
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
      customer: { email: "account@example.com" },
      settings: { displayMode: "overlay", theme: "light", locale: "en", allowLogout: false },
    },
  ]);
});

test("prefills returning customers by ID instead of passing an email", async () => {
  const { button, document, listeners } = fixture();
  const opened = [];

  await setupPaddleCheckout({
    document,
    window: {
      fetch: async () => ({
        ok: true,
        json: async () => ({
          transaction_id: "txn_returning",
          customer: { id: "ctm_returning" },
        }),
      }),
    },
    initializePaddle: async () => ({ Checkout: { open: (options) => opened.push(options) } }),
  });
  await listeners.click({ target: button });

  assert.deepEqual(opened, [{
    transactionId: "txn_returning",
    customer: { id: "ctm_returning" },
    settings: { displayMode: "overlay", theme: "light", locale: "en", allowLogout: false },
  }]);
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

test("failed initialization clears the transient price state", async () => {
  const { document, priceCurrency } = fixture({ priceId: "pri_test_yearly" });

  await setupPaddleCheckout({
    document,
    window: {},
    initializePaddle: async () => {
      throw new Error("network failed");
    },
    logger: { error() {} },
  });

  assert.equal(priceCurrency.textContent, "Price shown at checkout");
});

test("remounting checkout removes the previous click handler", async () => {
  const { document, listeners, button } = fixture();
  let requests = 0;
  const window = {
    fetch: async () => {
      requests++;
      return { ok: true, json: async () => ({ transaction_id: "txn_123" }) };
    },
  };
  const initializePaddle = async () => ({ Checkout: { open() {} } });
  const first = setupPaddleCheckout({ document, window, initializePaddle });
  await first;
  first.dispose();
  assert.equal(listeners.click, undefined);
  await setupPaddleCheckout({ document, window, initializePaddle });
  await listeners.click({ target: button });
  assert.equal(requests, 1);
});

test("disposing during Paddle initialization cancels the pending checkout", async () => {
  const { document, listeners, button } = fixture();
  const initialization = Promise.withResolvers();
  let requests = 0;
  const opened = [];
  const checkout = setupPaddleCheckout({
    document,
    window: {
      fetch: async () => { requests++; },
    },
    initializePaddle: () => initialization.promise,
  });
  const click = listeners.click({ target: button });
  checkout.dispose();
  initialization.resolve({ Checkout: { open: (options) => opened.push(options) } });
  await click;
  assert.equal(requests, 0);
  assert.deepEqual(opened, []);
});

test("disposing during transaction creation prevents opening checkout on another page", async () => {
  const { document, listeners, button } = fixture();
  const transaction = Promise.withResolvers();
  const requested = Promise.withResolvers();
  const opened = [];
  const checkout = setupPaddleCheckout({
    document,
    window: {
      fetch: () => {
        requested.resolve();
        return transaction.promise;
      },
    },
    initializePaddle: async () => ({ Checkout: { open: (options) => opened.push(options) } }),
  });
  await checkout;
  const click = listeners.click({ target: button });
  await requested.promise;
  checkout.dispose();
  transaction.resolve({ ok: true, json: async () => ({ transaction_id: "txn_123" }) });
  await click;
  assert.deepEqual(opened, []);
});

test("tracks only completed checkout, once, without customer or transaction data", async () => {
  const { document } = fixture();
  const events = [];
  const timers = [];
  const location = { href: "/settings/billing/lifetime" };
  let callback;
  const checkout = setupPaddleCheckout({
    document,
    window: {
      location,
      plausible: (...args) => events.push(args),
      setTimeout: (...args) => timers.push(args),
    },
    initializePaddle: async (options) => {
      callback = options.eventCallback;
      return { Checkout: { open() {} } };
    },
  });
  await checkout;
  callback({ name: "checkout.loaded" });
  assert.deepEqual(events, []);
  callback({ name: "checkout.completed", data: { email: "secret@example.com", transaction_id: "txn_private" } });
  callback({ name: "checkout.completed" });
  assert.deepEqual(events, [["Purchase", {}]]);
  assert.equal(timers.length, 1);
  assert.equal(timers[0][1], 5000);
  assert.equal(location.href, "/settings/billing/lifetime");
  timers[0][0]();
  assert.equal(location.href, "/settings/billing");
  checkout.dispose();
  callback({ name: "checkout.completed" });
  assert.equal(events.length, 1);
});
