import assert from "node:assert/strict";
import { rewritePricing } from "./pricing.ts";

Deno.test("worldwide rewrite replaces stale framing with the exact UTF-8 byte count", async () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "HTMLRewriter");
  const originalInfo = console.info;
  const logs: unknown[] = [];
  console.info = (prefix: string, payload: string) => {
    assert.equal(prefix, "shroud-pricing");
    logs.push(JSON.parse(payload));
  };
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
      request: new Request("https://example.test/pricing/?private=fixture", {
        headers: {
          "cdn-requestcountrycode": "US",
          "authorization": "Bearer fixture",
          "cookie": "private=fixture",
        },
      }),
      response,
    };
    const result = await rewritePricing(ctx);
    assert.equal(result, ctx.response);
    assert.equal(result.status, 404);
    assert.equal(result.headers.get("content-length"), "147");
    assert.equal(result.headers.get("cache-control"), "no-store");
    assert.equal(result.headers.get("x-bunny-deploy"), "fixture");
    assert.equal(
      result.headers.get("x-shroud-pricing-revision"),
      "framing-diagnostics-v1",
    );
    assert.deepEqual(logs, [
      {
        revision: "framing-diagnostics-v1",
        stage: "origin-response",
        method: "GET",
        status: 404,
        uk: false,
        originLength: "150",
        originEncoding: null,
        bodyless: false,
      },
      {
        revision: "framing-diagnostics-v1",
        stage: "before-buffer",
        rewrittenLength: "150",
        rewrittenEncoding: null,
      },
      {
        revision: "framing-diagnostics-v1",
        stage: "return-response",
        bodyBytes: 147,
        returnedLength: "147",
        returnedEncoding: null,
      },
    ]);
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
    console.info = originalInfo;
    if (original) Object.defineProperty(globalThis, "HTMLRewriter", original);
    else Reflect.deleteProperty(globalThis, "HTMLRewriter");
  }
});

Deno.test("worldwide HTML accepts a native Fetch response with immutable headers", async () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "HTMLRewriter");
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
});

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

for (const [method, status] of [["HEAD", 200], ["GET", 304]] as const) {
  Deno.test(`worldwide ${method} ${status} stays bodyless without rewriting`, async () => {
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
  });
}

Deno.test("non-HTML assets retain the original response and cache/framing headers", async () => {
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
});
