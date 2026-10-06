import assert from "node:assert/strict";
import test from "node:test";
import { filterAnalyticsEvent } from "./analytics.mjs";

test("retains OpenPanel events and redacts sensitive routes in all URL properties", () => {
  for (const [route, value, placeholder] of [
    ["users/reset_password", "SECRET", ":token"],
    ["users/confirm", "SECRET", ":token"],
    ["settings/confirm_email", "SECRET", ":token"],
    ["email-report", "SECRET", ":data"],
    ["alias", "address@example.com", ":address"],
    ["aliases", "address%40example.com", ":address"],
    ["inbox", "address%40example.com", ":address"],
    ["domain", "private.example.com", ":domain"],
    ["domains", "private.example.com", ":domain"],
  ]) {
    const event = {
      type: "track",
      payload: {
        name: "screen_view",
        profileId: "123",
        properties: {
          __path: `https://app.shroud.email/${route}/${value}?tab=settings#form`,
          __referrer: `https://app.shroud.email/${route}/${value}/`,
          href: `https://app.shroud.email/${route}/${value}`,
          __title: value,
          nested: { paths: [`/api/v1/${route}/${value}`] },
        },
      },
    };
    assert.equal(filterAnalyticsEvent(event), true);
    assert.deepEqual(event.payload, {
      name: "screen_view",
      profileId: "123",
      properties: {
        __path: `https://app.shroud.email/${route}/${placeholder}?tab=settings#form`,
        __referrer: `https://app.shroud.email/${route}/${placeholder}/`,
        href: `https://app.shroud.email/${route}/${placeholder}`,
        nested: { paths: [`/api/v1/${route}/${placeholder}`] },
      },
    });
    assert.ok(!JSON.stringify(event).includes(value));
    const sanitized = structuredClone(event);
    filterAnalyticsEvent(event);
    assert.deepEqual(event, sanitized);
  }
});

test("redacts inbox addresses and message IDs in message and attachment routes", () => {
  const event = {
    type: "track",
    payload: {
      name: "screen_view",
      properties: {
        __path: "/inbox/agent%40example.com/messages/713",
        __referrer: "/inbox/agent@example.com/messages/713?page=2",
        href: "/inbox/messages/713/attachments/0",
      },
    },
  };
  assert.equal(filterAnalyticsEvent(event), true);
  assert.deepEqual(event.payload.properties, {
    __path: "/inbox/:address/messages/:message",
    __referrer: "/inbox/:address/messages/:message?page=2",
    href: "/inbox/messages/:message/attachments/0",
  });
  const sanitized = structuredClone(event);
  filterAnalyticsEvent(event);
  assert.deepEqual(event, sanitized);
});

test("does not filter pages, events, or UTM attribution", () => {
  for (const name of ["screen_view", "link_out", "custom_event"]) {
    const event = {
      type: "track",
      payload: {
        name,
        properties: {
          __path:
            "https://app.shroud.email/users/register?utm_source=marketing",
          __referrer: "https://shroud.email/pricing/?utm_campaign=summer",
          paths: ["/aliases", "/domains"],
          text: "Read the documentation",
        },
      },
    };
    const original = structuredClone(event);
    assert.equal(filterAnalyticsEvent(event), true);
    assert.deepEqual(event, original);
  }
});
