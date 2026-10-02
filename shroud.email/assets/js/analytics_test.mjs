import assert from "node:assert/strict";
import test from "node:test";
import { transformAnalyticsRequest } from "./analytics.mjs";

test("leaves ordinary tracker payloads unchanged", () => {
  const payload = {
    n: "Purchase",
    u: "https://app.shroud.email/settings/billing?utm_source=newsletter&ref=partner#plans",
    d: "shroud.email",
    r: "https://search.example/results?q=email+privacy",
    v: 36,
    p: { tier: "annual" },
    $: { amount: 123, currency: "GBP" },
  };
  assert.deepEqual(transformAnalyticsRequest(payload), payload);
});

test("removes private alias-list searches without filtering campaign or other parameters", () => {
  const result = transformAnalyticsRequest({
    n: "pageview",
    u: "https://app.shroud.email/?query=private%40example.com&page=2&utm_source=newsletter&ref=partner&query=second-private-value",
  });
  assert.equal(
    result.u,
    "https://app.shroud.email/?page=2&utm_source=newsletter&ref=partner",
  );
});

test("normalizes alias, domain and email-report details without sending their values", () => {
  for (const [path, expected] of [
    ["/alias/private%40example.com", "/alias/:address"],
    ["/ali%61s/private%40example.com", "/alias/:address"],
    ["//alias//private%40example.com", "/alias/:address"],
    ["/domains/private.example", "/domains/:domain"],
    ["/%64omains/private.example", "/domains/:domain"],
    ["/email-report/encoded-private-report", "/email-report/:data"],
    ["/email%2Dreport/encoded-private-report", "/email-report/:data"],
    ["//email-report//encoded-private-report", "/email-report/:data"],
  ]) {
    const result = transformAnalyticsRequest({
      n: "pageview",
      u: `https://app.shroud.email${path}`,
    });
    assert.equal(result.u, `https://app.shroud.email${expected}`);
  }
});

test("normalizes only the sensitive pathname, leaving campaign handling to Plausible", () => {
  const result = transformAnalyticsRequest({
    n: "pageview",
    u: "https://app.shroud.email/alias/private%40example.com?utm_source=newsletter&utm_medium=email&utm_campaign=autumn+launch&ref=partner&utm_term=email+privacy&utm_content=footer#details",
  });
  assert.equal(
    result.u,
    "https://app.shroud.email/alias/:address?utm_source=newsletter&utm_medium=email&utm_campaign=autumn+launch&ref=partner&utm_term=email+privacy&utm_content=footer#details",
  );
});

test("denies sensitive routes but tracks new ordinary pages by default", () => {
  for (const path of [
    "/users/confirm/token",
    "/users/%63onfirm/token",
    "//users//confirm//token",
    "/users/reset_password/token",
    "/users/reset%5Fpassword/token",
    "/settings/confirm_email/token",
  ]) {
    assert.equal(
      transformAnalyticsRequest({
        n: "pageview",
        u: `https://app.shroud.email${path}`,
      }),
      null,
    );
  }
  for (const path of [
    "/new-feature",
    "/users/confirm",
    "/users/reset_password",
    "/administrator",
    "/admin/",
    "/debug_emails/123",
    "/feature_flags",
    "/proxy",
    "/email-report",
    "/email-reports/ordinary-page",
  ]) {
    assert.equal(
      transformAnalyticsRequest({
        n: "pageview",
        u: `https://app.shroud.email${path}`,
      }).u,
      `https://app.shroud.email${path}`,
    );
  }
  for (const host of [
    "localhost",
    "preview.onamp.dev",
    "shroud.email.attacker.test",
    "selfhost.example",
  ]) {
    assert.equal(
      transformAnalyticsRequest({ n: "pageview", u: `https://${host}/` }),
      null,
    );
  }
});

test("drops malformed encoded paths rather than throwing or leaking them", () => {
  for (const path of [
    "/ali%ZZas/private%40example.com",
    "/alias/%E0%A4",
    "/new-feature/%",
  ]) {
    assert.equal(
      transformAnalyticsRequest({
        n: "pageview",
        u: `https://app.shroud.email${path}`,
      }),
      null,
    );
  }
});
