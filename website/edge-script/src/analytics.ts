// Text responses cannot run browser analytics. Track requests at the CDN edge.
import { PostHog } from "npm:posthog-node@5.55.0/edge";

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
    ctx.request.method !== "GET" ||
    (!ctx.response.ok && ctx.response.status !== 304)
  ) {
    return ctx.response;
  }

  try {
    // The SDK has no waitUntil hook. Bound the awaited send so analytics failure
    // cannot prevent delivery. Each request is anonymous, not a visitor profile.
    const client = new PostHog(
      "phc_9q2mSOtde8Gj01Y41ok3beG5Lrt89INpUBrO46SqKD7",
      {
        host: "https://ph.btao.org",
        flushInterval: 0,
        fetchRetryCount: 0,
        requestTimeout: 1_000,
        disableGeoip: true,
        disableCompression: true,
        enableExceptionAutocapture: false,
        enableLocalEvaluation: false,
      },
    );
    await client.captureImmediate({
      distinctId: crypto.randomUUID(),
      event: "$pageview",
      properties: {
        $process_person_profile: false,
        $current_url: `${url.origin}${url.pathname}`,
        $host: url.hostname,
        $pathname: url.pathname,
        capture_source: "edge",
        format,
        status: ctx.response.status,
        $raw_user_agent:
          ctx.request.headers.get("user-agent")?.slice(0, 512) ?? "",
        country: ctx.request.headers.get("cdn-requestcountrycode"),
      },
    });
  } catch {
    // Analytics is best-effort; the original file response remains unchanged.
  }
  return ctx.response;
}
