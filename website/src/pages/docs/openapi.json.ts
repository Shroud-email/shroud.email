import type { APIRoute } from "astro";
import spec from "../../../../shroud.email/openapi.json?raw";

export const GET: APIRoute = () =>
  new Response(spec, {
    headers: { "Content-Type": "application/json" },
  });
