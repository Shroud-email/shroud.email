import { expect, it } from 'vitest';
import { messageHandler, validateMessage, type Sender } from '../../background/messages';
import { Auth } from '../../background/auth';
import { Api } from '../../background/api';
import { PreferencesStore } from '../../background/preferences';

it.each([
  { type: 'fetch', url: 'https://evil.example' },
  { type: 'account', access_token: 'stolen' },
  { type: 'create', input: { local_part: 'custom' } },
  { type: 'create', input: { domain: 42 } },
  { type: 'aliases', search: '', page: -1 },
  { type: 'aliases', search: '', page: 1, url: 'https://evil.example' },
  { type: 'preferences', patch: { instance: 'https://evil.example' } },
])('rejects malformed input %#', (value) => { expect(() => validateMessage(value)).toThrow(); });

it('accepts only defined creation and restricted domain operations', () => {
  expect(validateMessage({ type: 'create', input: { domain: 'custom.example', local_part: 'shop', title: 'Shop' } }).type).toBe('create');
  expect(validateMessage({ type: 'selected-domain', domain: 'custom.example' }).type).toBe('selected-domain');
});

it('rejects forged management and unregistered senders before any authenticated operation', async () => {
  let requests = 0;
  const data: Record<string, unknown> = { session: { instance: 'https://mail.example', email: 'u@example.net', access: 'secret', refresh: 'refresh', expiresAt: Date.now() + 100000 } };
  const storage = { get: async (k: string) => data[k], set: async (k: string, v: unknown) => { data[k] = v; }, remove: async (keys: string[]) => { keys.forEach((k) => delete data[k]); } };
  const fetcher: typeof fetch = async () => { requests++; return Response.json({ email_aliases: [], page_number: 1, page_size: 20, total_pages: 0, total_entries: 0 }); };
  const auth = new Auth({ storage, fetch: fetcher, now: Date.now, tabs: { create: async () => 1, update: async () => {}, remove: async () => {} } });
  const preferences = new PreferencesStore(auth, storage);
  const api = new Api(auth, fetcher, preferences, async () => true);
  const handler = messageHandler({ auth, preferences, api, extensionId: 'extension', popupUrl: 'chrome-extension://extension/popup.html', contentAllowed: async () => true, instanceAllowed: async () => true, open: async () => {}, updateInjection: async () => {} });
  const content: Sender = { id: 'extension', url: 'https://website.example', tab: { id: 7 }, frameId: 0 };
  for (const message of [{ type: 'login', instance: 'https://mail.example' }, { type: 'logout' }, { type: 'preferences', patch: { showIcon: true } }]) {
    expect(await handler(message, content)).toMatchObject({ ok: false, error: { kind: 'permission' } });
  }
  for (const sender of [{ ...content, id: 'foreign' }, { ...content, tab: undefined }, { ...content, frameId: undefined }, { id: 'extension', url: 'chrome-extension://foreign/popup.html' }]) {
    expect(await handler({ type: 'aliases', search: '', page: 1 }, sender)).toMatchObject({ ok: false, error: { kind: 'permission' } });
  }
  expect(requests).toBe(0);
  expect(await auth.identity()).not.toBeNull();
  expect(await handler({ type: 'aliases', search: '', page: 1 }, content)).toMatchObject({ ok: true, value: { email_aliases: [] } });
});
