import assert from "node:assert/strict";
import test from "node:test";
import { redactAnalyticsTokens } from "./analytics.mjs";

test("retains pageviews but redacts bearer tokens from URL and referrer properties", () => {
  for (const route of [
    "/users/reset_password",
    "/users/confirm",
    "/settings/confirm_email",
    "/email-report",
  ]) {
    const event = {
      event: "$pageview",
      uuid: "event-uuid",
      properties: {
        $current_url: `https://app.shroud.email${route}/SECRET-token?source=email#form`,
        $pathname: `${route}/SECRET-token`,
        $referrer: `https://app.shroud.email${route}/OTHER-token`,
        $set_once: { $initial_current_url: `https://app.shroud.email${route}/FIRST-token` },
        $process_person_profile: false,
      },
    };
    assert.deepEqual(redactAnalyticsTokens(event), {
      event: "$pageview",
      uuid: "event-uuid",
      properties: {
        $current_url: `https://app.shroud.email${route}/[redacted]?source=email#form`,
        $pathname: `${route}/[redacted]`,
        $referrer: `https://app.shroud.email${route}/[redacted]`,
        $set_once: { $initial_current_url: `https://app.shroud.email${route}/[redacted]` },
        $process_person_profile: false,
      },
    });
    assert.ok(event.properties.$current_url.includes("SECRET-token"));
  }
});

test("preserves regular page tracking and paid signup events without filtering", () => {
  const events = [
    {
      event: "$pageview",
      properties: {
        $current_url: "https://app.shroud.email/users/reset_password?source=nav",
        $pathname: "/users/confirm",
        $referrer: "https://shroud.email/pricing/?campaign=summer",
        paths: ["/alias/example@example.com", "/domains/example.com"],
      },
    },
    { event: "paid plan signed up", properties: { $process_person_profile: false } },
  ];
  for (const event of events) assert.deepEqual(redactAnalyticsTokens(event), event);
});
