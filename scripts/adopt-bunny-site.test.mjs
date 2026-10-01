import assert from "node:assert/strict";
import { test } from "node:test";
import { adoptSite, protectPricing } from "./adopt-bunny-site.mjs";

// Independent expected destinations: never derive these from the implementation.
for (const [environment, name, storageZoneId, pullZoneId, region, endpoint, otherStorage, otherPull] of [
  ["staging", "shroud-email-website-staging", 1687847, 6214167, "UK", "uk.storage.bunnycdn.com", 1604565, 6040372],
  ["production", "shroud-email-website", 1604565, 6040372, "DE", "storage.bunnycdn.com", 1687847, 6214167],
]) {
  const state = { version: 2, name, storageZoneId, pullZoneId, deploys: [] };
  function mockBunny({ metadata, storageId = storageZoneId, protectionFails = false, concurrentState = false, edgeRules = [] } = {}) {
    const calls = [];
    let reads = 0;
    const fetch = async (url, options = {}) => {
      const method = options.method ?? "GET";
      calls.push({ url, method, body: options.body && JSON.parse(options.body) });
      if (url === `https://api.bunny.net/storagezone/${storageZoneId}` && method === "GET") {
        return Response.json({ Id: storageZoneId, Name: name, Region: region, Password: "fake-storage-password" });
      }
      if (url === `https://api.bunny.net/pullzone/${pullZoneId}` && method === "GET") {
        return Response.json({ Id: pullZoneId, Name: name, StorageZoneId: storageId, OriginType: 2, EdgeRules: edgeRules });
      }
      if (url === `https://api.bunny.net/pullzone/${pullZoneId}/edgerules/addOrUpdate` && method === "POST") {
        const rule = JSON.parse(options.body);
        if (rule.Triggers.some((trigger) => trigger.PatternMatches.length > 5)) {
          return new Response("Too many patterns per trigger", { status: 400 });
        }
        return new Response("");
      }
      if (url.startsWith(`https://${name}.b-cdn.net/_bunny/site.json?`) && method === "GET") {
        if (protectionFails) throw new Error("Protection probe failed");
        return new Response("", { status: 403 });
      }
      if (url === `https://${endpoint}/${name}/_bunny/site.json`) {
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

  test(`${environment}: missing metadata requires explicit initialization and performs no writes`, async () => {
    const { fetch, calls } = mockBunny();
    await assert.rejects(adoptSite(environment, "fake-key", false, fetch), /initialize_sites=true/);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: initialization protects state before writing only the selected pair`, async () => {
    const { fetch, calls } = mockBunny();
    await adoptSite(environment, "fake-key", true, fetch);
    assert.deepEqual(calls.map((c) => c.method), ["GET", "GET", "GET", "POST", "GET", "GET", "PUT"]);
    const writes = calls.filter((c) => c.method !== "GET");
    assert.equal(writes[0].body.ActionType, 4);
    assert.deepEqual(writes[0].body.Triggers, [{ Type: 0, PatternMatches: ["*/_bunny/*"], PatternMatchingType: 0 }]);
    assert.deepEqual(writes[1].body, state);
    assert.ok(calls.every((c) => !c.url.includes(String(otherStorage)) && !c.url.includes(String(otherPull))));
  });

  test(`${environment}: existing metadata is never rewritten`, async () => {
    const { fetch, calls } = mockBunny({ metadata: { ...state, current: "abc", deploys: [{ id: "abc" }] } });
    await adoptSite(environment, "fake-key", true, fetch);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: wrong resource pair is rejected before any writes`, async () => {
    const { fetch, calls } = mockBunny({ storageId: otherStorage });
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /resource pair/);
    assert.equal(calls.length, 2);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: foreign metadata is rejected without overwriting it`, async () => {
    const { fetch, calls } = mockBunny({ metadata: { ...state, pullZoneId: otherPull } });
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /refusing to overwrite/);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: failed protection probe never writes metadata`, async () => {
    const { fetch, calls } = mockBunny({ protectionFails: true });
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /Protection probe failed/);
    assert.ok(!calls.some((c) => c.method === "PUT"));
  });

  test(`${environment}: metadata appearing during initialization is not overwritten`, async () => {
    const { fetch, calls } = mockBunny({ concurrentState: true });
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /changed during initialization/);
    assert.ok(!calls.some((c) => c.method === "PUT"));
  });

  const protection = {
    Description: "bunny sites: block site state access", Enabled: true,
    ActionType: 4, TriggerMatchingType: 0,
    Triggers: [{ Type: 0, PatternMatches: ["*/_bunny/*"], PatternMatchingType: 0 }],
  };

  test(`${environment}: conflicting state-protection rule is never overwritten`, async () => {
    const { fetch, calls } = mockBunny({ edgeRules: [{ ...protection, ActionType: 5 }] });
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /state-protection rule differs/);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: matching protection rule is reused without a rule write`, async () => {
    const { fetch, calls } = mockBunny({ edgeRules: [protection] });
    await adoptSite(environment, "fake-key", true, fetch);
    assert.ok(!calls.some((c) => c.method === "POST"));
    assert.deepEqual(calls.find((c) => c.method === "PUT").body, state);
  });

  test(`${environment}: pricing rule configures edge/browser cache bypass only on pricing URLs`, async () => {
    const { fetch, calls } = mockBunny();
    await protectPricing(environment, "fake-key", fetch);
    assert.deepEqual(calls.map((c) => c.method), ["GET", "POST"]);
    const rule = calls[1].body;
    assert.equal(rule.ActionType, 3);
    assert.equal(rule.ActionParameter1, "0");
    assert.deepEqual(rule.ExtraActions, [
      { ActionType: 16, ActionParameter1: "0" },
      { ActionType: 5, ActionParameter1: "Cache-Control", ActionParameter2: "no-store" },
    ]);
    assert.deepEqual(rule.Triggers, [{ Type: 0, PatternMatchingType: 0, PatternMatches: ["*/pricing", "*/pricing/", "*/pricing/index.html"] }]);
    assert.equal(rule.Enabled, true);
  });

  test(`${environment}: pricing rule is updated by GUID without replacing unrelated rules`, async () => {
    const { fetch, calls } = mockBunny({ edgeRules: [
      { Description: "bunny sites: serve the published deploy", Guid: "routing-guid" },
      { Description: "shroud: do not cache geo-localized pricing", Guid: "pricing-guid" },
    ] });
    await protectPricing(environment, "fake-key", fetch);
    assert.equal(calls[1].body.Guid, "pricing-guid");
    assert.equal(calls.length, 2);
  });

  test(`${environment}: pricing protection refuses an existing rule without a GUID before any writes`, async () => {
    const { fetch, calls } = mockBunny({ edgeRules: [{ Description: "shroud: do not cache geo-localized pricing" }] });
    await assert.rejects(protectPricing(environment, "fake-key", fetch), /no GUID/);
    assert.ok(calls.every((c) => c.method === "GET"));
  });

  test(`${environment}: pricing protection refuses the other environment before any writes`, async () => {
    const { fetch, calls } = mockBunny({ storageId: otherStorage });
    await assert.rejects(protectPricing(environment, "fake-key", fetch), /refusing pricing configuration/);
    assert.ok(calls.every((c) => c.method === "GET"));
  });
}

test("unknown or missing environment is rejected before any HTTP requests", async () => {
  const fetch = () => { throw new Error("Unexpected request"); };
  for (const environment of [undefined, "prod", "toString"]) {
    await assert.rejects(adoptSite(environment, "fake-key", true, fetch), /BUNNY_SITE_ENVIRONMENT/);
    await assert.rejects(protectPricing(environment, "fake-key", fetch), /BUNNY_SITE_ENVIRONMENT/);
  }
});
