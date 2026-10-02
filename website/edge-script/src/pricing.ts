// Bunny.net middleware edge script: geo-localized pricing.
//
// bunny.net injects `CDN-RequestCountryCode` (ISO-3166-1 alpha-2) on every
// request. We read it in onOriginResponse and rewrite the price inside any
// element carrying a `data-price-world` attribute to that attribute's value,
// using HTMLRewriter. Rewritten HTML is buffered to publish its exact byte length.
//
// The static HTML ships with UK prices as the default (£0 / £25/year), so if
// the script is ever disabled or the country header is missing, visitors see
// the UK prices.
//
// Caching: onOriginResponse runs BEFORE the response is cached, so if we
// rewrote and let it cache, every visitor would get the first visitor's
// price. We therefore set Cache-Control: no-store on HTML responses so the
// rewrite runs per-request. Static assets (JS/CSS/images/fonts) keep their
// original cache headers and are unaffected.
//
// Elements to rewrite are produced by the Pricing component, which tags the
// hero heading and the price table cells with `data-price` + `data-price-world`.

import "./bunny-globals.d.ts";

export const PRICING_REVISION = "directory-errors-v5";

// Country codes that should see the UK price. GB + the Crown dependencies
// (Guernsey, Jersey, Isle of Man) share the UK billing entity in Paddle.
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
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "client-response",
      method: ctx.request.method,
      status: ctx.response.status,
      directoryStyle,
    }),
  );
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
  } catch (error) {
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "directory-error-probe-failed",
        errorName: error instanceof Error ? error.name : "non-Error",
      }),
    );
    return ctx.response;
  }
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "directory-error-probe",
      status: fallback.status,
    }),
  );
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
  } catch (error) {
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "directory-error-body-failed",
        errorName: error instanceof Error ? error.name : "non-Error",
      }),
    );
    return ctx.response;
  }
  const headers = new Headers(fallback.headers);
  if (body !== null) {
    headers.delete("content-encoding");
    headers.delete("transfer-encoding");
    headers.set("content-length", String(body.byteLength));
  }
  headers.set("cache-control", "no-store");
  headers.set("x-shroud-pricing-revision", PRICING_REVISION);
  ctx.response = new Response(body, { status: 404, headers });
  return ctx.response;
}

// Rewritten HTML is a different representation with different byte offsets.
// Fetch it in full rather than forwarding the CDN's origin Range request.
export async function disableHtmlRanges(ctx: { request: Request }) {
  const url = new URL(ctx.request.url);
  const htmlRequest =
    (ctx.request.method === "GET" || ctx.request.method === "HEAD") &&
    (url.pathname.endsWith("/") || /\.html$/i.test(url.pathname));
  const range = ctx.request.headers.get("range");
  const ifRangeRequested = ctx.request.headers.has("if-range");
  if (htmlRequest && (range !== null || ifRangeRequested)) {
    ctx.request = new Request(ctx.request);
    ctx.request.headers.delete("range");
    ctx.request.headers.delete("if-range");
  }
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "origin-request",
      method: ctx.request.method,
      htmlRequest,
      deployPrefixedPath: /^\/deploys\//.test(url.pathname),
      indexPathSuffix: /\/index\.html$/.test(url.pathname),
      rangeRequested: range !== null,
      range:
        range !== null && range.length <= 128 && /^bytes=[0-9, -]+$/.test(range)
          ? range
          : null,
      ifRangeRequested,
      outgoingRangeRequested: ctx.request.headers.has("range"),
      outgoingIfRangeRequested: ctx.request.headers.has("if-range"),
    }),
  );
  return ctx.request;
}

export async function rewritePricing(
  ctx: { request: Request; response: Response },
) {
  const type = ctx.response.headers.get("content-type") ?? "";
  const country = ctx.request.headers.get("cdn-requestcountrycode");
  const pathname = new URL(ctx.request.url).pathname;
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "origin-response",
      method: ctx.request.method,
      status: ctx.response.status,
      country: country && /^[a-z]{2}$/i.test(country)
        ? country.toUpperCase()
        : null,
      uk: isUK(country),
      deployPrefixedPath: /^\/deploys\//.test(pathname),
      pricingPathSuffix: /\/pricing(?:\/|\/index\.html)?$/.test(pathname),
      indexPathSuffix: /\/index\.html$/.test(pathname),
      contentType: type,
      originLength: ctx.response.headers.get("content-length"),
      originEncoding: ctx.response.headers.get("content-encoding"),
      originCacheControl: ctx.response.headers.get("cache-control"),
      bodyless: ctx.response.body === null,
      bodyUsed: ctx.response.bodyUsed,
      bodyLocked: ctx.response.body?.locked ?? null,
    }),
  );

  // Only rewrite HTML responses.
  if (!type.includes("text/html")) {
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "non-html-pass-through",
      }),
    );
    return Promise.resolve(ctx.response);
  }

  // UK visitor (or unknown country): the static default is already in £, so
  // no rewrite needed. Still bypass the cache so a prior worldwide visitor's
  // rewritten copy can't leak to a UK visitor (or vice versa).
  if (isUK(country)) {
    const headers = new Headers(ctx.response.headers);
    headers.set("cache-control", "no-store");
    headers.set("x-shroud-pricing-revision", PRICING_REVISION);
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "uk-pass-through",
        returnedLength: headers.get("content-length"),
      }),
    );
    return Promise.resolve(
      new Response(ctx.response.body, {
        status: ctx.response.status,
        headers,
      }),
    );
  }

  // HEAD has no payload to measure; null-body statuses must stay bodyless.
  if (ctx.request.method === "HEAD" || ctx.response.body === null) {
    const headers = new Headers(ctx.response.headers);
    headers.delete("content-length");
    headers.set("cache-control", "no-store");
    headers.set("x-shroud-pricing-revision", PRICING_REVISION);
    ctx.response = new Response(null, {
      status: ctx.response.status,
      statusText: ctx.response.statusText,
      headers,
    });
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "bodyless-return",
        returnedLength: ctx.response.headers.get("content-length"),
      }),
    );
    return ctx.response;
  }

  // Worldwide visitor: replace each localized price with its worldwide
  // counterpart. The worldwide value is carried in the data-price-world
  // attribute on each <span data-price> (the hero heading + price cells).
  let priceReplacements = 0;
  const rewriter = new HTMLRewriter().on("[data-price-world]", {
    element(el: HtmlRewriterElement) {
      const world = el.getAttribute("data-price-world");
      if (world) {
        el.setInnerContent(world);
        priceReplacements++;
      }
    },
  });

  // Rewriting changes the byte count (£ is two UTF-8 bytes; $ is one).
  // Replace the context response too, without mutating Fetch-guarded headers.
  const inputHeaders = new Headers(ctx.response.headers);
  inputHeaders.delete("content-length");
  ctx.response = new Response(ctx.response.body, {
    status: ctx.response.status,
    statusText: ctx.response.statusText,
    headers: inputHeaders,
  });
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "before-transform",
      bodyUsed: ctx.response.bodyUsed,
      bodyLocked: ctx.response.body?.locked ?? null,
    }),
  );
  const rewritten = rewriter.transform(ctx.response);
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "before-buffer",
      inputLength: ctx.response.headers.get("content-length"),
      rewrittenLength: rewritten.headers.get("content-length"),
      rewrittenEncoding: rewritten.headers.get("content-encoding"),
      bodyUsed: rewritten.bodyUsed,
      bodyLocked: rewritten.body?.locked ?? null,
    }),
  );
  // Live staging still advertises the origin length despite the explicit override.
  // Explicitly override it with the actual output byte count, not string length.
  let body: ArrayBuffer;
  try {
    body = await rewritten.arrayBuffer();
  } catch (error) {
    console.log(
      "shroud-pricing",
      JSON.stringify({
        revision: PRICING_REVISION,
        stage: "buffer-error",
        errorName: error instanceof Error ? error.name : "non-Error",
        bodyUsed: rewritten.bodyUsed,
        bodyLocked: rewritten.body?.locked ?? null,
      }),
    );
    throw error;
  }
  const headers = new Headers(rewritten.headers);
  headers.set("content-length", String(body.byteLength));
  headers.set("cache-control", "no-store");
  headers.set("x-shroud-pricing-revision", PRICING_REVISION);
  ctx.response = new Response(body, {
    status: rewritten.status,
    headers,
  });
  console.log(
    "shroud-pricing",
    JSON.stringify({
      revision: PRICING_REVISION,
      stage: "return-response",
      status: ctx.response.status,
      priceReplacements,
      bodyBytes: body.byteLength,
      returnedLength: ctx.response.headers.get("content-length"),
      returnedEncoding: ctx.response.headers.get("content-encoding"),
      returnedCacheControl: ctx.response.headers.get("cache-control"),
      returnedRevision: ctx.response.headers.get("x-shroud-pricing-revision"),
      bodyUsed: ctx.response.bodyUsed,
      bodyLocked: ctx.response.body?.locked ?? null,
    }),
  );
  return ctx.response;
}
