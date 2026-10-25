export const WEBSITE_ORIGINS = ['https://*/*', 'http://*/*'];
export function instancePattern(instance: string): string {
  const url = new URL(instance);
  // Browser match patterns cover hosts, not individual ports. Networking still uses the exact origin.
  return `${url.protocol}//${url.hostname}/*`;
}
