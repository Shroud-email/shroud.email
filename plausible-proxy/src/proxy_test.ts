import { assertEquals } from "@std/assert";
import {
  EVENT_PATH,
  handleRequest,
  PROXY_SCRIPT,
  SCRIPT_PATH,
} from "./proxy.ts";

Deno.test("only exact routes and supported methods reach the upstream", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => {
    throw new Error("Unexpected upstream request");
  };
  try {
    for (
      const path of [
        `/prefix${SCRIPT_PATH}`,
        `${SCRIPT_PATH}/`,
        `${EVENT_PATH}/`,
        `${SCRIPT_PATH.slice(0, -3)}.extra.js`,
      ]
    ) {
      const response = await handleRequest(
        new Request(`https://proxy.test${path}`),
      );
      assertEquals(response.status, 404);
      assertEquals(response.headers.get("cache-control"), "no-store");
    }
    for (
      const [path, method, allow] of [
        [SCRIPT_PATH, "POST", "GET, HEAD"],
        [EVENT_PATH, "GET", "POST, OPTIONS"],
        [EVENT_PATH, "PUT", "POST, OPTIONS"],
      ]
    ) {
      const response = await handleRequest(
        new Request(`https://proxy.test${path}`, { method }),
      );
      assertEquals(response.status, 405);
      assertEquals(response.headers.get("allow"), allow);
      assertEquals(response.headers.get("cache-control"), "no-store");
    }
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("script uses the fixed upstream and is cacheable, including HEAD", async () => {
  const original = globalThis.fetch;
  const methods: string[] = [];
  globalThis.fetch = (url, init) => {
    assertEquals(url, PROXY_SCRIPT);
    methods.push(init!.method!);
    assertEquals(new Headers(init?.headers).has("cookie"), false);
    return Promise.resolve(
      new Response(
        init?.method === "HEAD" ? null : "/* personalized script */",
        {
          headers: { "Content-Type": "application/javascript" },
        },
      ),
    );
  };
  try {
    for (const method of ["GET", "HEAD"]) {
      const response = await handleRequest(
        new Request(
          `https://proxy.test${SCRIPT_PATH}?url=https://evil.test`,
          {
            method,
            headers: { Cookie: "session=secret" },
          },
        ),
      );
      assertEquals(response.status, 200);
      assertEquals(
        response.headers.get("cache-control"),
        "public, max-age=3600",
      );
      assertEquals(
        response.headers.get("content-type"),
        "application/javascript",
      );
      assertEquals(
        await response.text(),
        method === "HEAD" ? "" : "/* personalized script */",
      );
    }
    assertEquals(methods, ["GET", "HEAD"]);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("event preserves payload, visitor metadata and upstream errors, not credentials", async () => {
  const original = globalThis.fetch;
  const payload =
    '{"name":"pageview","domain":"example.com","url":"https://example.com/path?x=2"}';
  globalThis.fetch = async (url, init) => {
    assertEquals(url, "https://plausible.io/api/event");
    assertEquals(init?.redirect, "manual");
    const outgoing = new Request(String(url), init);
    assertEquals(outgoing.method, "POST");
    assertEquals(await outgoing.text(), payload);
    for (
      const [header, value] of [
        ["content-type", "text/plain"],
        ["user-agent", "Test browser"],
        ["referer", "https://example.com/path"],
        ["origin", "https://example.com"],
        ["x-forwarded-for", "2001:db8::42"],
      ]
    ) assertEquals(outgoing.headers.get(header), value);
    for (
      const name of [
        "cookie",
        "authorization",
        "host",
        "x-custom-secret",
        "x-real-ip",
      ]
    ) {
      assertEquals(outgoing.headers.has(name), false);
    }
    return new Response("Rate limited", {
      status: 429,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Retry-After": "30",
        "Set-Cookie": "unexpected=value",
        "Cache-Control": "public, max-age=600",
      },
    });
  };
  try {
    const response = await handleRequest(
      new Request(`https://proxy.test${EVENT_PATH}`, {
        method: "POST",
        body: payload,
        headers: {
          "Content-Type": "text/plain",
          "User-Agent": "Test browser",
          Referer: "https://example.com/path",
          Origin: "https://example.com",
          "X-Real-IP": "2001:db8::42",
          "X-Forwarded-For": "192.0.2.99",
          Cookie: "session=secret",
          Authorization: "Bearer secret",
          Host: "proxy.test",
          "X-Custom-Secret": "secret",
        },
      }),
    );
    assertEquals(response.status, 429);
    assertEquals(await response.text(), "Rate limited");
    assertEquals(response.headers.get("access-control-allow-origin"), "*");
    assertEquals(response.headers.get("retry-after"), "30");
    assertEquals(response.headers.has("set-cookie"), false);
    assertEquals(response.headers.get("cache-control"), "no-store");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("preflight is forwarded without trusting a caller's forwarded IP", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (_url, init) => {
    assertEquals(init?.method, "OPTIONS");
    assertEquals(init?.body, undefined);
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("origin"), "https://example.com");
    assertEquals(headers.get("access-control-request-method"), "POST");
    assertEquals(headers.get("access-control-request-headers"), "content-type");
    assertEquals(headers.has("x-forwarded-for"), false);
    return Promise.resolve(
      new Response(null, {
        status: 204,
        headers: { "Access-Control-Allow-Origin": "*" },
      }),
    );
  };
  try {
    const response = await handleRequest(
      new Request(`https://proxy.test${EVENT_PATH}`, {
        method: "OPTIONS",
        headers: {
          Origin: "https://example.com",
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": "content-type",
          "X-Forwarded-For": "192.0.2.99",
        },
      }),
    );
    assertEquals(response.status, 204);
    assertEquals(response.headers.get("access-control-allow-origin"), "*");
    assertEquals(response.headers.get("cache-control"), "no-store");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("script errors and network failures are never cached", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(new Response("Not found", { status: 404 }));
    const missing = await handleRequest(
      new Request(`https://proxy.test${SCRIPT_PATH}`),
    );
    assertEquals(missing.status, 404);
    assertEquals(await missing.text(), "Not found");
    assertEquals(missing.headers.get("cache-control"), "no-store");
    globalThis.fetch = () => Promise.reject(new TypeError("Connection failed"));
    const failed = await handleRequest(
      new Request(`https://proxy.test${EVENT_PATH}`, {
        method: "POST",
        body: "{}",
      }),
    );
    assertEquals(failed.status, 502);
    assertEquals(await failed.text(), "Upstream unavailable");
    assertEquals(failed.headers.get("cache-control"), "no-store");
  } finally {
    globalThis.fetch = original;
  }
});
