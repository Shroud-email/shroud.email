import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const window = {};
runInNewContext(readFileSync(new URL("../vendor/components.js", import.meta.url), "utf8"), { window });

function menu(disabled) {
  const items = disabled.map((value, index) => ({
    id: `item-${index}`,
    getAttribute: name => name === "aria-disabled" && value ? "true" : null,
  }));
  const instance = window.AlpineComponents.menu();
  instance.$el = { querySelectorAll: () => items };
  instance.$refs = { "menu-items": { focus() {} } };
  instance.$nextTick = callback => callback();
  instance.init();
  return instance;
}

test("arrow navigation skips disabled items without changing their original indices", () => {
  const instance = menu([true, false, true, false, true]);
  for (const [method, index] of [
    ["onArrowDown", 1], ["onArrowDown", 3], ["onArrowDown", 3],
    ["onArrowUp", 1], ["onArrowUp", 1],
  ]) {
    instance[method]();
    assert.equal(instance.activeIndex, index);
    assert.equal(instance.activeDescendant, `item-${index}`);
  }
  instance.open = false;
  instance.onArrowUp();
  assert.equal(instance.activeIndex, 3);
  assert.equal(instance.activeDescendant, "item-3");
});

test("Enter selects the first enabled item and click opening clears stale selection", () => {
  const instance = menu([true, false, true]);
  instance.onButtonEnter();
  assert.equal(instance.activeIndex, 1);
  assert.equal(instance.activeDescendant, "item-1");
  instance.onButtonEnter();
  assert.equal(instance.open, false);
  instance.onButtonClick();
  assert.equal(instance.activeIndex, -1);
  assert.equal(instance.activeDescendant, null);
});

test("menus without disabled items retain boundary behavior", () => {
  const instance = menu([false, false]);
  instance.onArrowDown();
  assert.equal(instance.activeDescendant, "item-0");
  instance.onArrowDown();
  instance.onArrowDown();
  assert.equal(instance.activeDescendant, "item-1");
  instance.onArrowUp();
  assert.equal(instance.activeDescendant, "item-0");
});

test("menus with no enabled items do not select a disabled item", () => {
  for (const method of ["onArrowDown", "onArrowUp", "onButtonEnter"]) {
    const instance = menu([true, true]);
    instance[method]();
    assert.equal(instance.activeDescendant, null);
  }
});
