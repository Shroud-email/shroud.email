// Text responses cannot run browser analytics. Track requests at the CDN edge.
export async function trackTextRequest(ctx: {
  request: Request;
  response: Response;
}) {
  const url = new URL(ctx.request.url);
  const format =
    url.pathname === "/llms.txt"
      ? "llms.txt"
      : url.pathname === "/llms-full.txt"
        ? "llms-full.txt"
        : url.pathname.endsWith(".md")
          ? "markdown"
          : null;
  if (
    !format ||
    url.origin !== "https://shroud.email" ||
    ctx.request.method !== "GET" ||
    (!ctx.response.ok && ctx.response.status !== 304)
  ) {
    return ctx.response;
  }

  try {
    // Bunny Env Configuration supplies these at runtime, never at build time.
    const clientId = Deno.env.get("OPENPANEL_CLIENT_ID");
    const secret = Deno.env.get("OPENPANEL_CLIENT_SECRET");
    if (!clientId || !secret) return ctx.response;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 1_000);
    try {
      const response = await fetch("https://panel.shroud.email/api/track", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "openpanel-client-id": clientId,
          "openpanel-client-secret": secret,
        },
        signal: controller.signal,
        body: JSON.stringify({
          type: "track",
          payload: {
            name: "screen_view",
            properties: {
              __path: `${url.origin}${url.pathname}`,
              __timestamp: new Date().toISOString(),
              capture_source: "edge",
              format,
              status: ctx.response.status,
              country: ctx.request.headers.get("cdn-requestcountrycode"),
            },
          },
        }),
      });
      await response.body?.cancel();
    } finally {
      clearTimeout(timeout);
    }
  } catch {
    // Best-effort, no retries: analytics must not prevent file delivery.
  }
  return ctx.response;
}
