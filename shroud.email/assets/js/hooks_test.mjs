import assert from "node:assert/strict";
import test from "node:test";

import * as Hooks from "./hooks.js";

test("copy hook copies the element text and updates its tooltip", async () => {
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
    async writeText(text) {
      assert.equal(text, "hello@example.com");
    },
  });

  hook.el = element;
  hook.mounted();
  await listeners.click();

  assert.deepEqual(tooltipContents, ["Copy to clipboard", "Copied!"]);

  hook.destroyed();
  assert.equal(tooltipDestroyed, true);
  assert.equal(listeners.click, undefined);
});
