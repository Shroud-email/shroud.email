// Bunny.net middleware edge script: geo-localized pricing.
//
// bunny.net injects `CDN-RequestCountryCode` (ISO-3166-1 alpha-2) on every
// request. We read it in onOriginResponse and rewrite the price inside any
// element carrying a `data-price-world` attribute to that attribute's value,
// using HTMLRewriter (streaming, no buffering).
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

import * as BunnySDK from "https://esm.sh/@bunny.net/edgescript-sdk@0.12.0";
import "./bunny-globals.d.ts";

// Country codes that should see the UK price. GB + the Crown dependencies
// (Guernsey, Jersey, Isle of Man) share the UK billing entity in Paddle.
const UK_COUNTRY_CODES = new Set(["GB", "GG", "JE", "IM"]);

function isUK(country: string | null): boolean {
  return country !== null && UK_COUNTRY_CODES.has(country.toUpperCase());
}

// The `url` is only used for local development; in production bunny proxies
// to the origin configured on the Pull Zone. Point it at the live site so
// `deno task dev` fetches real HTML when testing locally.
const ORIGIN_URL = "https://shroud.email/";

BunnySDK.net.http
  .servePullZone({ url: ORIGIN_URL })
  .onOriginResponse((ctx) => {
    // Only rewrite HTML responses.
    const type = ctx.response.headers.get("content-type") ?? "";
    if (!type.includes("text/html")) {
      return Promise.resolve(ctx.response);
    }

    const country = ctx.request.headers.get("cdn-requestcountrycode");

    // UK visitor (or unknown country): the static default is already in £, so
    // no rewrite needed. Still bypass the cache so a prior worldwide visitor's
    // rewritten copy can't leak to a UK visitor (or vice versa).
    if (isUK(country)) {
      const headers = new Headers(ctx.response.headers);
      headers.set("cache-control", "no-store");
      return Promise.resolve(
        new Response(ctx.response.body, {
          status: ctx.response.status,
          headers,
        }),
      );
    }

    // Worldwide visitor: replace each localized price with its worldwide
    // counterpart. The worldwide value is carried in the data-price-world
    // attribute on each <span data-price> (the hero heading + price cells).
    const rewriter = new HTMLRewriter().on("[data-price-world]", {
      element(el: HtmlRewriterElement) {
        const world = el.getAttribute("data-price-world");
        if (world) el.setInnerContent(world);
      },
    });

    const rewritten = rewriter.transform(ctx.response);
    const headers = new Headers(rewritten.headers);
    headers.set("cache-control", "no-store");
    return Promise.resolve(
      new Response(rewritten.body, {
        status: rewritten.status,
        headers,
      }),
    );
  });
