// App analytics: previews and self-hosting are excluded.
export function transformAnalyticsRequest(payload) {
  const url = new URL(payload.u);
  if (url.hostname !== "app.shroud.email") return null;

  // Phoenix discards empty path segments and decodes them before routing.
  let path;
  try {
    path = `/${url.pathname.split("/").filter(Boolean).map(decodeURIComponent).join("/")}`;
  } catch {
    return null;
  }

  // Deny sensitive routes; new ordinary pages are tracked without configuration.
  if (
    /^\/(?:users\/(?:confirm|reset_password)\/|settings\/confirm_email\/)/.test(
      path,
    )
  )
    return null;
  if (path.startsWith("/alias/")) url.pathname = "/alias/:address";
  if (path.startsWith("/domains/")) url.pathname = "/domains/:domain";
  if (path.startsWith("/email-report/")) url.pathname = "/email-report/:data";
  // The alias-list search contains private account data, not campaign attribution.
  if (path === "/") url.searchParams.delete("query");

  return { ...payload, u: url.href };
}
