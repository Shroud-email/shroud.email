// Replace this with the personalized script URL in Plausible's site settings.
export const PROXY_SCRIPT =
  "https://plausible.io/js/pa-5AG4aRFlACAj4itoPfLBC.js";
export const SCRIPT_PATH = "/qwerty/script.js";
export const EVENT_PATH = "/qwerty/event";

export async function handleRequest(request: Request): Promise<Response> {
  const pathname = new URL(request.url).pathname;
  const isScript = pathname === SCRIPT_PATH;
  if (!isScript && pathname !== EVENT_PATH) {
    return new Response(null, {
      status: 404,
      headers: { "Cache-Control": "no-store" },
    });
  }

  const allowed = isScript ? ["GET", "HEAD"] : ["POST", "OPTIONS"];
  if (!allowed.includes(request.method)) {
    return new Response(null, {
      status: 405,
      headers: { Allow: allowed.join(", "), "Cache-Control": "no-store" },
    });
  }

  // Only forward headers needed for analytics/CORS, never site credentials.
  const headers = new Headers({ "Accept-Encoding": "identity" });
  if (!isScript) {
    for (
      const name of [
        "content-type",
        "user-agent",
        "referer",
        "origin",
        "access-control-request-method",
        "access-control-request-headers",
      ]
    ) {
      const value = request.headers.get(name);
      if (value !== null) headers.set(name, value);
    }
    // Bunny replaces X-Real-IP with the visitor's IP at the CDN boundary.
    const ip = request.headers.get("x-real-ip");
    if (ip) headers.set("X-Forwarded-For", ip);
  }

  try {
    const upstream = await fetch(
      isScript ? PROXY_SCRIPT : "https://plausible.io/api/event",
      {
        method: request.method,
        headers,
        body: request.method === "POST" ? request.body : undefined,
        redirect: "manual",
      },
    );
    const responseHeaders = new Headers(upstream.headers);
    responseHeaders.delete("set-cookie");
    // Fetch may decode the body; let Bunny calculate transport headers.
    responseHeaders.delete("content-encoding");
    responseHeaders.delete("content-length");
    responseHeaders.set(
      "Cache-Control",
      isScript && upstream.ok ? "public, max-age=3600" : "no-store",
    );
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  } catch {
    return new Response("Upstream unavailable", {
      status: 502,
      headers: { "Cache-Control": "no-store" },
    });
  }
}
