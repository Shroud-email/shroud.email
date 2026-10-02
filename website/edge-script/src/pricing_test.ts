import assert from "node:assert/strict";
import { rewritePricing } from "./pricing.ts";

Deno.test("worldwide rewrite removes the upstream length before changing UTF-8 byte counts", async () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "HTMLRewriter");
  let upstreamHeaders: Headers;
  // Preserve a snapshot of upstream framing on the transformed response.
  // Exercise header removal on both the context and the returned response.
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
      '<span data-price-world="$35/year">£25/year</span><span data-price-world="$0">£0</span><span data-price-world="$35/year">£25/year</span>';
    const response = new Response(html, {
      status: 404,
      headers: {
        "content-type": "text/html; charset=utf-8",
        "content-length": String(new TextEncoder().encode(html).length),
        "x-bunny-deploy": "fixture",
      },
    });
    upstreamHeaders = new Headers(response.headers);
    const result = await rewritePricing({
      request: new Request("https://example.test/pricing/", {
        headers: { "cdn-requestcountrycode": "US" },
      }),
      response,
    });
    assert.equal(result.status, 404);
    assert.equal(result.headers.get("content-length"), null);
    assert.equal(result.headers.get("cache-control"), "no-store");
    assert.equal(result.headers.get("x-bunny-deploy"), "fixture");
    const rewritten = await result.text();
    assert.equal(
      rewritten,
      '<span data-price-world="$35/year">$35/year</span><span data-price-world="$0">$0</span><span data-price-world="$35/year">$35/year</span>',
    );
    assert.equal(
      new TextEncoder().encode(rewritten).length,
      new TextEncoder().encode(html).length - 3,
    );
  } finally {
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
    assert.equal(result.headers.get("content-length"), null);
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
