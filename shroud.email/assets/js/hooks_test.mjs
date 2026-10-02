import assert from "node:assert/strict";
import test from "node:test";

import * as Hooks from "./hooks.js";

function fixture(writeText) {
  const listeners = {};
  const element = {
    dataset: { clipboardText: "hello@example.com" },
    addEventListener(name, listener) {
      listeners[name] = listener;
    },
    removeEventListener(name, listener) {
      if (listeners[name] === listener) delete listeners[name];
    },
  };
  const tooltipContents = [];
  let tooltipDestroyed = false;
  const hook = Hooks.createCopyToClipboardHook({
    createTooltip(_element, options) {
      tooltipContents.push(options.content);

      return {
        destroy() {
          tooltipDestroyed = true;
        },
        setContent(content) {
          tooltipContents.push(content);
        },
      };
    },
    writeText,
  });

  hook.el = element;
  hook.mounted();

  return { hook, listeners, tooltipContents, tooltipDestroyed: () => tooltipDestroyed };
}

test("copy hook copies the current element text and cleans up on removal", async () => {
  const copied = [];
  const { hook, listeners, tooltipContents, tooltipDestroyed } = fixture(async text => {
    copied.push(text);
  });
  await listeners.click();

  hook.el.dataset.clipboardText = "updated@example.com";
  await listeners.click();
  assert.deepEqual(copied, ["hello@example.com", "updated@example.com"]);
  assert.deepEqual(tooltipContents, ["Copy to clipboard", "Copied!", "Copied!"]);

  hook.destroyed();
  assert.equal(tooltipDestroyed(), true);
  assert.equal(listeners.click, undefined);
});

test("repeat clicks restart the feedback timer and removal cancels it", async context => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const { hook, listeners, tooltipContents } = fixture(async () => {});
  await listeners.click();
  context.mock.timers.tick(1500);
  await listeners.click();
  context.mock.timers.tick(500);
  assert.deepEqual(tooltipContents, ["Copy to clipboard", "Copied!", "Copied!"]);
  context.mock.timers.tick(1499);
  assert.equal(tooltipContents.at(-1), "Copied!");
  context.mock.timers.tick(1);
  assert.equal(tooltipContents.at(-1), "Copy to clipboard");

  await listeners.click();
  hook.destroyed();
  context.mock.timers.tick(2000);
  assert.equal(tooltipContents.at(-1), "Copied!");
});

test("a denied clipboard write shows failure feedback and resets it", async context => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const { hook, listeners, tooltipContents } = fixture(async () => {
    throw new Error("Clipboard permission denied");
  });

  await assert.doesNotReject(listeners.click());
  assert.deepEqual(tooltipContents, ["Copy to clipboard", "Copy failed — please copy manually"]);
  context.mock.timers.tick(2000);
  assert.equal(tooltipContents.at(-1), "Copy to clipboard");
  hook.destroyed();
});

test("an unavailable clipboard API shows failure feedback", async () => {
  const { hook, listeners, tooltipContents } = fixture(() => {
    throw new TypeError("Clipboard API unavailable");
  });
  await assert.doesNotReject(listeners.click());
  assert.equal(tooltipContents.at(-1), "Copy failed — please copy manually");
  hook.destroyed();
});

test("backup-code copy opens its custom alert only when copying fails", async () => {
  let denied = false;
  const copied = [];
  const { hook, listeners } = fixture(async text => {
    if (denied) throw new Error("Denied");
    copied.push(text);
  });
  hook.el.dataset.clipboardText = "12345678\n87654321";
  hook.el.dataset.copyErrorEvent = "backup_copy_failed";
  const events = [];
  hook.pushEvent = (...args) => events.push(args);
  await listeners.click();
  assert.deepEqual(copied, ["12345678\n87654321"]);
  assert.deepEqual(events, []);
  denied = true;
  await listeners.click();
  assert.deepEqual(events, [["backup_copy_failed", {}]]);
  hook.destroyed();
});
