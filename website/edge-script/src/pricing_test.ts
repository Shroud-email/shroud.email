import assert from "node:assert/strict";
import {
  disableHtmlRanges,
  repairDirectoryNotFound,
  rewritePricing,
} from "./pricing.ts";

Deno.test(
  "HTML GET and HEAD drop range headers without changing URLs or other headers",
  async () => {
    for (const [method, input] of [
      [
        "GET",
        "http://origin.test:9000/deploys/release-42/docs/privacy/?lang=en&next=%2Fpricing%2F",
      ],
      ["HEAD", "http://origin.test:9000/deploys/release-42/pricing/"],
      ["GET", "https://example.test/"],
      ["GET", "https://example.test/pricing/index.html?lang=en"],
    ]) {
      const request = new Request(input, {
        method,
        headers: {
          "cdn-requestcountrycode": "GB",
          authorization: "Bearer fixture",
          range: "bytes=0-99",
          "if-range": '"fixture-etag"',
        },
      });
      const ctx = { request };
      const result = await disableHtmlRanges(ctx);
      assert.equal(result, ctx.request);
      assert.equal(result.url, input);
      assert.equal(result.method, method);
      assert.deepEqual(
        [...result.headers],
        [
          ["authorization", "Bearer fixture"],
          ["cdn-requestcountrycode", "GB"],
        ],
      );
      assert.equal(request.headers.get("range"), "bytes=0-99");
      assert.equal(request.headers.get("if-range"), '"fixture-etag"');
    }
    const ifRangeOnly = await disableHtmlRanges({
      request: new Request("https://example.test/", {
        headers: { "if-range": '"etag"' },
      }),
    });
    assert.equal(ifRangeOnly.headers.has("if-range"), false);
    const complete = new Request("https://example.test/pricing/");
    assert.equal(await disableHtmlRanges({ request: complete }), complete);
  },
);

Deno.test(
  "asset ranges, extensionless paths and non-GET/HEAD methods remain untouched",
  async () => {
    for (const [method, path] of [
      ["GET", "/style.css"],
      ["GET", "/video.mp4"],
      ["GET", "/pricing"],
      ["POST", "/pricing/"],
      ["OPTIONS", "/"],
    ]) {
      const request = new Request(`https://example.test${path}`, {
        method,
        body: method === "POST" ? "fixture" : undefined,
        headers: { range: "bytes=0-99", "if-range": '"etag"' },
      });
      const result = await disableHtmlRanges({ request });
      assert.equal(result, request);
      assert.equal(result.headers.get("range"), "bytes=0-99");
      assert.equal(result.headers.get("if-range"), '"etag"');
      if (method === "POST") assert.equal(await result.text(), "fixture");
    }
  },
);

Deno.test(
  "worldwide rewrite replaces stale framing with the exact UTF-8 byte count",
  async () => {
    const original = Object.getOwnPropertyDescriptor(
      globalThis,
      "HTMLRewriter",
    );
    let upstreamHeaders: Headers;
    // Preserve a snapshot of upstream framing on the transformed response.
    // Exercise an explicit override even when the rewriter retains old headers.
    class TestRewriter {
      handler!: ElementHandler;
      on(selector: string, handler: ElementHandler) {
        assert.equal(selector, "[data-price-world]");
        this.handler = handler;
        return this;
      }
      transform(response: Response) {
        assert.equal(response.headers.get("content-length"), null);
        const handler = this.handler;
        const stream = new ReadableStream({
          async start(controller) {
            const html = await response.text();
            const rewritten = html.replace(
              /(<span data-price-world="([^"]+)">)([^<]*)(<\/span>)/g,
              (_match, start, world, content, end) => {
                handler.element!({
                  getAttribute: () => world,
                  setInnerContent(value: string) {
                    content = value;
                  },
                } as unknown as HtmlRewriterElement);
                return start + content + end;
              },
            );
            controller.enqueue(new TextEncoder().encode(rewritten));
            controller.close();
          },
        });
        return new Response(stream, {
          status: response.status,
          headers: upstreamHeaders,
        });
      }
    }
    Object.defineProperty(globalThis, "HTMLRewriter", {
      value: TestRewriter,
      configurable: true,
    });
    try {
      const html =
        '<span data-price-world="$35/year">£25/year</span><span data-price-world="$0">£0</span><span data-price-world="$35/year">£25/year</span><p>π☃</p>';
      const response = new Response(html, {
        status: 404,
        headers: {
          "content-type": "text/html; charset=utf-8",
          "content-length": String(new TextEncoder().encode(html).length),
          "x-bunny-deploy": "fixture",
        },
      });
      upstreamHeaders = new Headers(response.headers);
      const ctx = {
        request: new Request(
          "https://example.test/deploys/release/pricing/index.html?private=fixture",
          {
            headers: {
              "cdn-requestcountrycode": "US",
              authorization: "Bearer fixture",
              cookie: "private=fixture",
            },
          },
        ),
        response,
      };
      const result = await rewritePricing(ctx);
      assert.equal(result, ctx.response);
      assert.equal(result.status, 404);
      assert.equal(result.headers.get("content-length"), "147");
      assert.equal(result.headers.get("cache-control"), "no-store");
      assert.equal(result.headers.get("x-bunny-deploy"), "fixture");
      assert.equal(result.headers.has("x-shroud-pricing-revision"), false);
      const rewritten = await result.text();
      assert.equal(
        rewritten,
        '<span data-price-world="$35/year">$35/year</span><span data-price-world="$0">$0</span><span data-price-world="$35/year">$35/year</span><p>π☃</p>',
      );
      assert.equal(
        new TextEncoder().encode(rewritten).length,
        new TextEncoder().encode(html).length - 3,
      );
    } finally {
      if (original) Object.defineProperty(globalThis, "HTMLRewriter", original);
      else Reflect.deleteProperty(globalThis, "HTMLRewriter");
    }
  },
);

Deno.test(
  "worldwide HTML accepts a native Fetch response with immutable headers",
  async () => {
    const original = Object.getOwnPropertyDescriptor(
      globalThis,
      "HTMLRewriter",
    );
    const response = await fetch("data:text/html,<p>plain HTML</p>");
    assert.throws(() => response.headers.delete("content-length"), TypeError);
    class TestRewriter {
      on() {
        return this;
      }
      transform(input: Response) {
        assert.notEqual(input, response);
        assert.doesNotThrow(() => input.headers.delete("content-length"));
        return input;
      }
    }
    Object.defineProperty(globalThis, "HTMLRewriter", {
      value: TestRewriter,
      configurable: true,
    });
    try {
      const result = await rewritePricing({
        request: new Request("https://example.test/pricing/", {
          headers: { "cdn-requestcountrycode": "US" },
        }),
        response,
      });
      assert.equal(await result.text(), "<p>plain HTML</p>");
      assert.equal(result.headers.get("content-length"), "17");
    } finally {
      if (original) Object.defineProperty(globalThis, "HTMLRewriter", original);
      else Reflect.deleteProperty(globalThis, "HTMLRewriter");
    }
  },
);

Deno.test(
  "rewrite buffer failures propagate without hiding failure",
  async () => {
    const original = Object.getOwnPropertyDescriptor(
      globalThis,
      "HTMLRewriter",
    );
    const failure = new TypeError("private fixture data");
    class TestRewriter {
      on() {
        return this;
      }
      transform() {
        return new Response(
          new ReadableStream({
            start(controller) {
              controller.error(failure);
            },
          }),
        );
      }
    }
    Object.defineProperty(globalThis, "HTMLRewriter", {
      value: TestRewriter,
      configurable: true,
    });
    try {
      await assert.rejects(
        rewritePricing({
          request: new Request("https://example.test/any-html-route/"),
          response: new Response("body", {
            headers: { "content-type": "text/html" },
          }),
        }),
        (error) => error === failure,
      );
    } finally {
      if (original) Object.defineProperty(globalThis, "HTMLRewriter", original);
      else Reflect.deleteProperty(globalThis, "HTMLRewriter");
    }
  },
);

Deno.test("UK HTML retains its unchanged body length", async () => {
  const html = "<p>£25/year</p>";
  const response = new Response(html, {
    headers: { "content-type": "text/html", "content-length": "16" },
  });
  const result = await rewritePricing({
    request: new Request("https://example.test/pricing/", {
      headers: { "cdn-requestcountrycode": "GB" },
    }),
    response,
  });
  assert.equal(await result.text(), html);
  assert.equal(result.headers.get("content-length"), "16");
  assert.equal(result.headers.get("cache-control"), "no-store");
});

for (const [method, status] of [
  ["HEAD", 200],
  ["GET", 304],
] as const) {
  Deno.test(
    `worldwide ${method} ${status} stays bodyless without rewriting`,
    async () => {
      // No HTMLRewriter is installed: invoking it would fail this test.
      const ctx = {
        request: new Request("https://example.test/pricing/", {
          method,
          headers: { "cdn-requestcountrycode": "US" },
        }),
        response: new Response(null, {
          status,
          headers: { "content-type": "text/html", "content-length": "150" },
        }),
      };
      const result = await rewritePricing(ctx);
      assert.equal(result, ctx.response);
      assert.equal(result.status, status);
      assert.equal(result.body, null);
      assert.equal(result.headers.get("content-length"), null);
      assert.equal(result.headers.get("cache-control"), "no-store");
    },
  );
}

Deno.test(
  "non-HTML assets retain the original response and cache/framing headers",
  async () => {
    const response = new Response("body", {
      headers: {
        "content-type": "text/css",
        "content-length": "4",
        "cache-control": "public, max-age=86400",
      },
    });
    const result = await rewritePricing({
      request: new Request("https://example.test/style.css", {
        headers: { "cdn-requestcountrycode": "US" },
      }),
      response,
    });
    assert.equal(result, response);
    assert.equal(result.headers.get("content-length"), "4");
    assert.equal(result.headers.get("cache-control"), "public, max-age=86400");
  },
);

Deno.test(
  "directory 400 uses the actual index-file 404, preserving GET/HEAD and query",
  async () => {
    const originalFetch = globalThis.fetch;
    try {
      for (const [method, path] of [
        ["GET", "/missing/"],
        ["HEAD", "/missing"],
      ]) {
        let probes = 0;
        globalThis.fetch = (input, init) => {
          probes++;
          assert.equal(
            String(input),
            "https://example.test/missing/index.html?lang=en",
          );
          assert.equal(init?.method, method);
          assert.equal(init?.redirect, "manual");
          assert.ok(init?.signal);
          const headers = new Headers(init?.headers);
          assert.equal(headers.get("authorization"), "Bearer fixture");
          assert.equal(headers.has("range"), false);
          assert.equal(headers.has("if-range"), false);
          return Promise.resolve(
            new Response(method === "HEAD" ? null : "Real custom 404", {
              status: 404,
              headers: {
                "content-type": "text/html",
                "cache-control": "public, max-age=60",
              },
            }),
          );
        };
        const ctx = {
          request: new Request(`https://example.test${path}?lang=en`, {
            method,
            headers: {
              authorization: "Bearer fixture",
              range: "bytes=0-99",
              "if-range": '"etag"',
            },
          }),
          response: new Response("Original 400", { status: 400 }),
        };
        const result = await repairDirectoryNotFound(ctx);
        assert.equal(probes, 1);
        assert.equal(result, ctx.response);
        assert.equal(result.status, 404);
        assert.equal(result.headers.get("content-type"), "text/html");
        assert.equal(result.headers.get("cache-control"), "no-store");
        if (method === "GET") {
          assert.equal(result.headers.get("content-length"), "15");
        }
        assert.equal(result.headers.has("x-shroud-pricing-revision"), false);
        if (method === "HEAD") assert.equal(result.body, null);
        else assert.equal(await result.text(), "Real custom 404");
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "client handler leaves successful, blocked, file and non-read requests alone",
  async () => {
    const originalFetch = globalThis.fetch;
    let probes = 0;
    globalThis.fetch = () => {
      probes++;
      throw new Error("Must not probe");
    };
    try {
      for (const [status, method, path] of [
        [200, "GET", "/pricing/"],
        [404, "GET", "/missing/"],
        [403, "GET", "/_bunny/"],
        [400, "GET", "/missing/index.html"],
        [400, "GET", "/missing.css"],
        [400, "POST", "/missing/"],
      ] as const) {
        const response = new Response("Original", { status });
        const result = await repairDirectoryNotFound({
          request: new Request(`https://example.test${path}`, { method }),
          response,
        });
        assert.equal(result, response);
        assert.equal(await result.text(), "Original");
      }
      assert.equal(probes, 0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "an index probe must really return 404; redirects, successes and failures preserve 400",
  async () => {
    const originalFetch = globalThis.fetch;
    try {
      for (const status of [
        200,
        301,
        400,
        403,
        500,
        "network-error",
      ] as const) {
        globalThis.fetch = () => {
          if (status === "network-error") {
            return Promise.reject(new TypeError("Private fixture data"));
          }
          return Promise.resolve(new Response("Probe", { status }));
        };
        const response = new Response("Original 400", { status: 400 });
        const result = await repairDirectoryNotFound({
          request: new Request("https://example.test/missing/"),
          response,
        });
        assert.equal(result, response);
        assert.equal(await result.text(), "Original 400");
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);

Deno.test(
  "failed probe body reads and cleanup preserve the original 400",
  async () => {
    const originalFetch = globalThis.fetch;
    try {
      for (const status of [404, 500]) {
        globalThis.fetch = () =>
          Promise.resolve(
            new Response(
              new ReadableStream({
                start(controller) {
                  controller.error(new TypeError("Private stream error"));
                },
              }),
              { status },
            ),
          );
        const response = new Response("Original 400", { status: 400 });
        const ctx = {
          request: new Request("https://example.test/missing/"),
          response,
        };
        assert.equal(await repairDirectoryNotFound(ctx), response);
        assert.equal(ctx.response, response);
        assert.equal(await response.text(), "Original 400");
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);
