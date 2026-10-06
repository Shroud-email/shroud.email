const tokenPath =
  /(\/(?:users\/(?:reset_password|confirm)|settings\/confirm_email)\/)[^/?#\s]+/g;
const reportPath = /(\/email-report\/)[^/?#\s]+/g;
const aliasPath = /(\/alias(?:es)?\/)[^/?#\s]+/g;
const inboxMessagePath = /(\/inbox\/(?:[^/?#\s]+\/)?messages\/)[^/?#\s]+/g;
const inboxPath = /(\/inbox\/)(?!messages(?:\/|[?#\s]|$))[^/?#\s]+/g;
const domainPath = /(\/domains?\/)[^/?#\s]+/g;

function redactPaths(value) {
  if (typeof value === "string") {
    return value
      .replace(tokenPath, "$1:token")
      .replace(reportPath, "$1:data")
      .replace(aliasPath, "$1:address")
      .replace(inboxMessagePath, "$1:message")
      .replace(inboxPath, "$1:address")
      .replace(domainPath, "$1:domain");
  }
  if (Array.isArray(value)) return value.map(redactPaths);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, property]) => [
        key,
        redactPaths(property),
      ]),
    );
  }
  return value;
}

// OpenPanel sends this same envelope after the filter returns true.
export function filterAnalyticsEvent(event) {
  if (event.type === "track") {
    event.payload.properties = redactPaths(event.payload.properties);
    // Page titles can contain alias/domain addresses.
    delete event.payload.properties?.__title;
  }
  return true;
}
