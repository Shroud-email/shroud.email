export function normalizeInstance(input: string): string {
  const value = input.trim();
  // Reject syntax that URL would silently normalize into a different origin/path.
  if (!/^https?:\/\/[^/?#\\\s]+\/?$/.test(value)) {
    throw new Error('Enter a server origin without a path, query or fragment');
  }
  const url = new URL(value);
  const loopback = url.hostname === 'localhost' || url.hostname === '[::1]' || /^127\./.test(url.hostname);
  if (url.username || url.password || (url.protocol !== 'https:' && !loopback)) {
    throw new Error('Use HTTPS, or a loopback address for local development');
  }
  return url.origin;
}
