const tokenPath = /(\/(?:users\/(?:reset_password|confirm)|settings\/confirm_email|email-report)\/)[^/?#\s]+/g;
const aliasPath = /(\/alias(?:es)?\/)[^/?#\s]+/g;
const domainPath = /(\/domains?\/)[^/?#\s]+/g;

function redactPaths(value) {
  if (typeof value === "string") {
    return value
      .replace(tokenPath, "$1[redacted]")
      .replace(aliasPath, "$1:address")
      .replace(domainPath, "$1:domain");
  }
  if (Array.isArray(value)) return value.map(redactPaths);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, property]) => [key, redactPaths(property)]),
    );
  }
  return value;
}

// Apply to URL, pathname, referrer, and nested initial-page properties alike.
export function sanitizeAnalyticsEvent(event) {
  return { ...event, properties: redactPaths(event.properties) };
}
