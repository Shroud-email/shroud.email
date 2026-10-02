// Bunny.net middleware edge script: geo-localized pricing.
// The static HTML contains UK prices. HTMLRewriter replaces elements carrying
// data-price-world for worldwide visitors. HTML is never cached across countries;
// static assets retain their original cache headers.

import "./bunny-globals.d.ts";

// UK and Crown dependencies share the UK billing entity in Paddle.
const UK_COUNTRY_CODES = new Set(["GB", "GG", "JE", "IM"]);

function isUK(country: string | null): boolean {
  return country !== null && UK_COUNTRY_CODES.has(country.toUpperCase());
}

// Native Storage returns an empty 400 for some missing directory URLs. Check
// the explicit index file before replacing that response; other 400s stay 400.
// This hook requires the Pull Zone's "Run script before cache" setting.
export async function repairDirectoryNotFound(
  ctx: { request: Request; response: Response },
) {
  const url = new URL(ctx.request.url);
  const directoryStyle = url.pathname.endsWith("/") ||
    !url.pathname.split("/").at(-1)!.includes(".");
  if (
    ctx.response.status !== 400 || !directoryStyle ||
    (ctx.request.method !== "GET" && ctx.request.method !== "HEAD")
  ) {
    return ctx.response;
  }

  url.pathname += url.pathname.endsWith("/") ? "index.html" : "/index.html";
  const requestHeaders = new Headers(ctx.request.headers);
  requestHeaders.delete("range");
  requestHeaders.delete("if-range");
  let fallback: Response;
  try {
    // The explicit .html path cannot enter this fallback again. Do not follow
    // redirects or turn an origin/network failure into a fabricated 404.
    fallback = await fetch(url, {
      method: ctx.request.method,
      headers: requestHeaders,
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    return ctx.response;
  }
  if (fallback.status !== 404) {
    try {
      await fallback.body?.cancel();
    } catch {
      // A failed cleanup must not replace the original error response.
    }
    return ctx.response;
  }

  let body: ArrayBuffer | null;
  try {
    body = ctx.request.method === "HEAD" ? null : await fallback.arrayBuffer();
  } catch {
    return ctx.response;
  }
  const headers = new Headers(fallback.headers);
  if (body !== null) {
    headers.delete("content-encoding");
    headers.delete("transfer-encoding");
    headers.set("content-length", String(body.byteLength));
  }
  headers.set("cache-control", "no-store");
  ctx.response = new Response(body, { status: 404, headers });
  return ctx.response;
}

// Rewritten HTML has different byte offsets. Bunny injects origin ranges even
// for full client requests; remove them for HTML to avoid stale response framing.
export async function disableHtmlRanges(ctx: { request: Request }) {
  const url = new URL(ctx.request.url);
  const htmlRequest =
    (ctx.request.method === "GET" || ctx.request.method === "HEAD") &&
    (url.pathname.endsWith("/") || /\.html$/i.test(url.pathname));
  if (
    htmlRequest &&
    (ctx.request.headers.has("range") || ctx.request.headers.has("if-range"))
  ) {
    ctx.request = new Request(ctx.request);
    ctx.request.headers.delete("range");
    ctx.request.headers.delete("if-range");
  }
  return ctx.request;
}

export async function rewritePricing(
  ctx: { request: Request; response: Response },
) {
  const type = ctx.response.headers.get("content-type") ?? "";
  const country = ctx.request.headers.get("cdn-requestcountrycode");

  if (!type.includes("text/html")) {
    return ctx.response;
  }

  // UK prices are already baked into the page. Still prevent cross-country caching.
  if (isUK(country)) {
    const headers = new Headers(ctx.response.headers);
    headers.set("cache-control", "no-store");
    return new Response(ctx.response.body, {
      status: ctx.response.status,
      headers,
    });
  }

  // HEAD has no payload to measure; null-body statuses must stay bodyless.
  if (ctx.request.method === "HEAD" || ctx.response.body === null) {
    const headers = new Headers(ctx.response.headers);
    headers.delete("content-length");
    headers.set("cache-control", "no-store");
    ctx.response = new Response(null, {
      status: ctx.response.status,
      statusText: ctx.response.statusText,
      headers,
    });
    return ctx.response;
  }

  const rewriter = new HTMLRewriter().on("[data-price-world]", {
    element(el: HtmlRewriterElement) {
      const world = el.getAttribute("data-price-world");
      if (world) el.setInnerContent(world);
    },
  });

  // £ occupies two UTF-8 bytes; $ occupies one. Replace the context response
  // without mutating Fetch-guarded headers, then measure the rewritten bytes.
  const inputHeaders = new Headers(ctx.response.headers);
  inputHeaders.delete("content-length");
  ctx.response = new Response(ctx.response.body, {
    status: ctx.response.status,
    statusText: ctx.response.statusText,
    headers: inputHeaders,
  });
  const rewritten = rewriter.transform(ctx.response);
  const body = await rewritten.arrayBuffer();
  const headers = new Headers(rewritten.headers);
  headers.set("content-length", String(body.byteLength));
  headers.set("cache-control", "no-store");
  ctx.response = new Response(body, {
    status: rewritten.status,
    headers,
  });
  return ctx.response;
}
