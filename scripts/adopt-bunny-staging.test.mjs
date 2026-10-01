import assert from "node:assert/strict";
import { test } from "node:test";
import { adoptStaging, protectStagingPricing } from "./adopt-bunny-staging.mjs";

const state = {
  version: 2, name: "shroud-email-website-staging", storageZoneId: 1687847,
  pullZoneId: 6214167, deploys: [],
};

function mockBunny({ metadata, storageId = 1687847, protectionFails = false, concurrentState = false, edgeRules = [] } = {}) {
  const calls = [];
  let reads = 0;
  const fetch = async (url, options = {}) => {
    const method = options.method ?? "GET";
    calls.push({ url, method, body: options.body && JSON.parse(options.body) });
    if (url === "https://api.bunny.net/storagezone/1687847" && method === "GET") {
      return Response.json({ Id: 1687847, Name: state.name, Region: "UK", Password: "fake-storage-password" });
    }
    if (url === "https://api.bunny.net/pullzone/6214167" && method === "GET") {
      return Response.json({ Id: 6214167, Name: state.name, StorageZoneId: storageId, OriginType: 2, EdgeRules: edgeRules });
    }
    if (url === "https://api.bunny.net/pullzone/6214167/edgerules/addOrUpdate" && method === "POST") {
      const rule = JSON.parse(options.body);
      if (rule.Triggers.some((trigger) => trigger.PatternMatches.length > 5)) {
        return new Response("Too many patterns per trigger", { status: 400 });
      }
      return new Response("");
    }
    if (url.startsWith("https://shroud-email-website-staging.b-cdn.net/_bunny/site.json?") && method === "GET") {
      if (protectionFails) throw new Error("Protection probe failed");
      return new Response("", { status: 403 });
    }
    if (url === "https://uk.storage.bunnycdn.com/shroud-email-website-staging/_bunny/site.json") {
      if (method === "GET") {
        reads++;
        return metadata || (concurrentState && reads > 1)
          ? Response.json(metadata ?? state) : new Response("", { status: 404 });
      }
      if (method === "PUT") return new Response("");
    }
    throw new Error(`Unexpected request: ${method} ${url}`);
  };
  return { fetch, calls };
}

test("missing metadata requires explicit initialization and performs no writes", async () => {
  const { fetch, calls } = mockBunny();
  await assert.rejects(adoptStaging("fake-key", false, fetch), /initialize_sites=true/);
  assert.ok(calls.every((c) => c.method === "GET"));
});

test("initialization protects state before writing only staging metadata", async () => {
  const { fetch, calls } = mockBunny();
  await adoptStaging("fake-key", true, fetch);
  assert.deepEqual(calls.map((c) => c.method), ["GET", "GET", "GET", "POST", "GET", "GET", "PUT"]);
  const writes = calls.filter((c) => c.method !== "GET");
  assert.equal(writes[0].body.ActionType, 4);
  assert.deepEqual(writes[0].body.Triggers, [{ Type: 0, PatternMatches: ["*/_bunny/*"], PatternMatchingType: 0 }]);
  assert.deepEqual(writes[1].body, state);
  assert.ok(calls.every((c) => !c.url.includes("1604565") && !c.url.includes("6040372")));
});

test("existing metadata is never rewritten", async () => {
  const { fetch, calls } = mockBunny({ metadata: { ...state, current: "abc", deploys: [{ id: "abc" }] } });
  await adoptStaging("fake-key", true, fetch);
  assert.ok(calls.every((c) => c.method === "GET"));
});

test("wrong resource pair is rejected before any writes", async () => {
  const { fetch, calls } = mockBunny({ storageId: 1604565 });
  await assert.rejects(adoptStaging("fake-key", true, fetch), /resource pair/);
  assert.equal(calls.length, 2);
  assert.ok(calls.every((c) => c.method === "GET"));
});

test("foreign metadata is rejected without overwriting it", async () => {
  const { fetch, calls } = mockBunny({ metadata: { ...state, pullZoneId: 6040372 } });
  await assert.rejects(adoptStaging("fake-key", true, fetch), /refusing to overwrite/);
  assert.ok(calls.every((c) => c.method === "GET"));
});

test("failed protection probe never writes metadata", async () => {
  const { fetch, calls } = mockBunny({ protectionFails: true });
  await assert.rejects(adoptStaging("fake-key", true, fetch), /Protection probe failed/);
  assert.ok(!calls.some((c) => c.method === "PUT"));
});

test("metadata appearing during initialization is not overwritten", async () => {
  const { fetch, calls } = mockBunny({ concurrentState: true });
  await assert.rejects(adoptStaging("fake-key", true, fetch), /changed during initialization/);
  assert.ok(!calls.some((c) => c.method === "PUT"));
});

const protection = {
  Description: "bunny sites: block site state access", Enabled: true,
  ActionType: 4, TriggerMatchingType: 0,
  Triggers: [{ Type: 0, PatternMatches: ["*/_bunny/*"], PatternMatchingType: 0 }],
};

test("conflicting state-protection rule is never overwritten", async () => {
  const { fetch, calls } = mockBunny({ edgeRules: [{ ...protection, ActionType: 5 }] });
  await assert.rejects(adoptStaging("fake-key", true, fetch), /state-protection rule differs/);
  assert.ok(calls.every((c) => c.method === "GET"));
});

test("matching protection rule is reused without a rule write", async () => {
  const { fetch, calls } = mockBunny({ edgeRules: [protection] });
  await adoptStaging("fake-key", true, fetch);
  assert.ok(!calls.some((c) => c.method === "POST"));
  assert.deepEqual(calls.find((c) => c.method === "PUT").body, state);
});

test("pricing protection bypasses edge and browser cache only on pricing page URLs", async () => {
  const { fetch, calls } = mockBunny();
  await protectStagingPricing("fake-key", fetch);
  assert.deepEqual(calls.map((c) => c.method), ["GET", "POST"]);
  const rule = calls[1].body;
  assert.equal(rule.ActionType, 3);
  assert.equal(rule.ActionParameter1, "0");
  assert.deepEqual(rule.ExtraActions, [
    { ActionType: 16, ActionParameter1: "0" },
    { ActionType: 5, ActionParameter1: "Cache-Control", ActionParameter2: "no-store" },
  ]);
  assert.deepEqual(rule.Triggers[0].PatternMatches, [
    "*/pricing", "*/pricing/", "*/pricing/index.html",
  ]);
  assert.equal(rule.Triggers[0].PatternMatchingType, 0);
  assert.equal(rule.Triggers[0].Type, 0);
  assert.equal(rule.Enabled, true);
});

test("pricing rule is updated by GUID without replacing unrelated rules", async () => {
  const { fetch, calls } = mockBunny({ edgeRules: [
    { Description: "bunny sites: serve the published deploy", Guid: "routing-guid" },
    { Description: "shroud: do not cache geo-localized pricing", Guid: "pricing-guid" },
  ] });
  await protectStagingPricing("fake-key", fetch);
  assert.equal(calls[1].body.Guid, "pricing-guid");
  assert.equal(calls.length, 2);
});

test("pricing protection refuses a production storage ID before any writes", async () => {
  const { fetch, calls } = mockBunny({ storageId: 1604565 });
  await assert.rejects(protectStagingPricing("fake-key", fetch), /refusing pricing configuration/);
  assert.ok(calls.every((c) => c.method === "GET"));
});
