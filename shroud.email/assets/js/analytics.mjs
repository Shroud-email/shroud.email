const tokenPath = /(\/(?:users\/(?:reset_password|confirm)|settings\/confirm_email|email-report)\/)[^/?#\s]+/g;

function redactTokens(value) {
  if (typeof value === "string") return value.replace(tokenPath, "$1[redacted]");
  if (Array.isArray(value)) return value.map(redactTokens);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, property]) => [key, redactTokens(property)]),
    );
  }
  return value;
}

// Apply to URL, pathname, referrer, and nested initial-page properties alike.
export function redactAnalyticsTokens(event) {
  return { ...event, properties: redactTokens(event.properties) };
}
