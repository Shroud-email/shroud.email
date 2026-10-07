const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { expo } = require("../app.json");

test("native identities and the HTTPS association domain are stable", () => {
  assert.deepEqual(expo.platforms, ["ios", "android"]);
  assert.equal(expo.scheme, "shroud");
  assert.equal(expo.ios.bundleIdentifier, "email.shroud.app");
  assert.equal(expo.android.package, "email.shroud.app");
  assert.deepEqual(expo.ios.associatedDomains, ["applinks:app.shroud.email"]);
});

test("verified Android links only claim current screens and the auth callback", () => {
  const [filter] = expo.android.intentFilters;
  assert.equal(expo.android.intentFilters.length, 1);
  assert.equal(filter.action, "VIEW");
  assert.equal(filter.autoVerify, true);
  assert.deepEqual(filter.category, ["BROWSABLE", "DEFAULT"]);
  assert.deepEqual(
    filter.data,
    ["/", "/explore", "/oauth/callback"].map((route) => ({
      scheme: "https",
      host: "app.shroud.email",
      path: route,
    })),
  );
  for (const screen of ["index", "explore", "oauth/callback"]) {
    assert.ok(fs.existsSync(path.join(__dirname, `../src/app/${screen}.tsx`)));
  }
});
