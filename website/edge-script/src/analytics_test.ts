import assert from "node:assert/strict";
import { trackTextRequest } from "./analytics.ts";

// Dummy credentials only; fetch is mocked in every test.
Deno.env.set("OPENPANEL_CLIENT_ID", "test-client");
Deno.env.set("OPENPANEL_CLIENT_SECRET", "test-secret");

Deno.test(
  "text requests send anonymous metadata and preserve the response",
  async () => {
    const originalFetch = globalThis.fetch;
    let calls = 0;
    try {
      for (const [path, format, status] of [
        ["/llms.txt", "llms.txt", 200],
        ["/llms-full.txt", "llms-full.txt", 200],
        ["/docs/api/aliases.md", "markdown", 206],
        ["/home.md", "markdown", 304],
      ] as const) {
        let captured: Request | undefined;
        let sent = false;
        globalThis.fetch = async (input, init) => {
          calls++;
          captured = new Request(input, init);
          await new Promise((resolve) => setTimeout(resolve, 5));
          sent = true;
          return new Response("{}", { status: 200 });
        };
        const response = new Response(status === 304 ? null : "# Content\n", {
          status,
          headers: { "cache-control": "public, max-age=3600", etag: '"text"' },
        });
        const result = await trackTextRequest({
          request: new Request(`https://shroud.email${path}?private=value`, {
            headers: {
              "user-agent": "ExampleBot/1.0",
              "cdn-requestcountrycode": "GB",
              cookie: "session=private",
              "x-forwarded-for": "192.0.2.1",
              referer: "https://example.test/?private=value",
            },
          }),
          response,
        });
        assert.equal(sent, true);
        assert.ok(captured);
        assert.equal(captured.url, "https://panel.shroud.email/api/track");
        assert.equal(captured.method, "POST");
        assert.equal(captured.headers.get("content-type"), "application/json");
        assert.equal(captured.headers.has("cookie"), false);
        assert.equal(captured.headers.has("x-forwarded-for"), false);
        assert.equal(captured.headers.has("x-client-ip"), false);
        assert.equal(captured.headers.has("user-agent"), false);
        assert.equal(
          captured.headers.get("openpanel-client-id"),
          "test-client",
        );
        assert.equal(
          captured.headers.get("openpanel-client-secret"),
          "test-secret",
        );
        const payload = await captured.json();
        assert.equal(payload.type, "track");
        const event = payload.payload;
        assert.equal(event.name, "screen_view");
        assert.equal(
          new Date(event.properties.__timestamp).toISOString(),
          event.properties.__timestamp,
        );
        assert.deepEqual(event.properties, {
          __path: `https://shroud.email${path}`,
          __timestamp: event.properties.__timestamp,
          capture_source: "edge",
          format,
          status,
          country: "GB",
        });
        assert.equal(result, response);
        assert.equal(
          result.headers.get("cache-control"),
          "public, max-age=3600",
        );
        assert.equal(await result.text(), status === 304 ? "" : "# Content\n");
      }
      assert.equal(calls, 4);
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "unrelated, failed and non-GET requests do not send analytics",
  async () => {
    const originalFetch = globalThis.fetch;
    try {
      let calls = 0;
      globalThis.fetch = async () => {
        calls++;
        return new Response(null);
      };
      for (const [path, method, status] of [
        ["/docs/privacy/", "GET", 200],
        ["/robots.txt", "GET", 200],
        ["/other/llms.txt", "GET", 200],
        ["/llms.txt", "HEAD", 200],
        ["/home.md", "POST", 200],
        ["/missing.md", "GET", 404],
        ["/llms-full.txt", "GET", 500],
        ["/home.md", "GET", 302],
      ] as const) {
        const response = new Response(null, { status });
        assert.equal(
          await trackTextRequest({
            request: new Request(`https://shroud.email${path}`, { method }),
            response,
          }),
          response,
        );
      }
      assert.equal(calls, 0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "analytics errors and timeouts do not change file delivery",
  async () => {
    const originalFetch = globalThis.fetch;
    try {
      for (const failure of ["network", "timeout", "http"] as const) {
        let calls = 0;
        let aborted = false;
        globalThis.fetch = async (_input, init) => {
          calls++;
          if (failure === "http") return new Response(null, { status: 503 });
          if (failure === "network") throw new Error("Offline");
          await new Promise<void>((_resolve, reject) => {
            // Fail the test if the wrapper does not abort the request.
            const deadline = setTimeout(
              () => reject(new Error("No abort")),
              2_000,
            );
            init!.signal!.addEventListener(
              "abort",
              () => {
                aborted = true;
                clearTimeout(deadline);
                reject(init!.signal!.reason);
              },
              {
                once: true,
              },
            );
          });
          throw new Error("Unreachable");
        };
        const response = new Response("# Content\n");
        assert.equal(
          await trackTextRequest({
            request: new Request("https://shroud.email/llms.txt"),
            response,
          }),
          response,
        );
        assert.equal(calls, 1);
        assert.equal(aborted, failure === "timeout");
        assert.equal(await response.text(), "# Content\n");
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "missing configuration and nonproduction requests never send",
  async () => {
    const originalFetch = globalThis.fetch;
    let calls = 0;
    try {
      globalThis.fetch = () => {
        calls++;
        throw new Error("Unexpected analytics send");
      };
      for (const [clientId, secret, origin] of [
        [undefined, "test-secret", "https://shroud.email"],
        ["", "test-secret", "https://shroud.email"],
        ["test-client", undefined, "https://shroud.email"],
        ["test-client", "", "https://shroud.email"],
        [
          "test-client",
          "test-secret",
          "https://shroud-email-website-staging.b-cdn.net",
        ],
        ["test-client", "test-secret", "http://localhost:8080"],
      ]) {
        if (clientId === undefined) Deno.env.delete("OPENPANEL_CLIENT_ID");
        else Deno.env.set("OPENPANEL_CLIENT_ID", clientId);
        if (secret === undefined) Deno.env.delete("OPENPANEL_CLIENT_SECRET");
        else Deno.env.set("OPENPANEL_CLIENT_SECRET", secret);
        const response = new Response("text");
        assert.equal(
          await trackTextRequest({
            request: new Request(`${origin}/llms.txt`),
            response,
          }),
          response,
        );
      }
      assert.equal(calls, 0);
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.set("OPENPANEL_CLIENT_ID", "test-client");
      Deno.env.set("OPENPANEL_CLIENT_SECRET", "test-secret");
    }
  },
);
