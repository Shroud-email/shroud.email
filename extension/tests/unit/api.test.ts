import { expect, it } from 'vitest';
import { Api } from '../../background/api';
import { PreferencesStore } from '../../background/preferences';
import { Auth, type AuthDependencies } from '../../background/auth';

it('normalizes all domain pages, encoded search, recent aliases and stable limit errors', async () => {
  const data: Record<string, unknown> = { session: { instance: 'https://mail.example', email: 'u@example.net', access: 'secret', refresh: 'refresh', expiresAt: Date.now() + 100000 } };
  const urls: URL[] = [];
  const alias = { address: 'recent@other.example', title: 'A & B', notes: null, enabled: true, forwarded: 7, blocked: 2, blocked_addresses: [] };
  const deps: AuthDependencies = {
    storage: { get: async (k) => data[k], set: async (k, v) => { data[k] = v; }, remove: async (keys) => { keys.forEach((k) => delete data[k]); } },
    tabs: { create: async () => 1, update: async () => {}, remove: async () => {} }, now: Date.now,
    fetch: async (input, init) => {
      const url = new URL(String(input)); urls.push(url);
      if (init?.method === 'POST') return Response.json({ code: 'free_limit_reached', error: 'Upgrade' }, { status: 403 });
      if (url.pathname.endsWith('alias-capabilities')) return Response.json({ alias_count: 5, alias_limit: 5, can_create: false, default_domain: 'default.example' });
      if (url.pathname.endsWith('domains')) return Response.json({ domains: [{ domain: url.searchParams.get('page') === '2' ? 'second.example' : 'first.example' }], page_number: Number(url.searchParams.get('page')), page_size: 1, total_pages: 2, total_entries: 2 });
      return Response.json({ email_aliases: [alias], page_number: 1, page_size: 3, total_entries: 1, total_pages: 1 });
    },
  };
  const auth = new Auth(deps);
  const preferences = new PreferencesStore(auth, deps.storage);
  const api = new Api(auth, deps.fetch, preferences, async () => false);
  await preferences.update({ selectedDomain: 'removed.example' });
  const account = await api.account();
  expect(account!.domains).toEqual(['default.example', 'first.example', 'second.example']);
  expect(account!.preferences.selectedDomain).toBe('default.example');
  expect(JSON.stringify(account)).not.toContain('secret');
  expect((await api.aliases('A & B+', 2)).email_aliases).toEqual([alias]);
  expect(urls.at(-1)!.searchParams.get('search')).toBe('A & B+');
  expect(urls.at(-1)!.searchParams.get('page')).toBe('2');
  await api.aliases('', 99, true);
  expect(urls.at(-1)!.searchParams.get('enabled')).toBe('true');
  expect(urls.at(-1)!.searchParams.get('page_size')).toBe('3');
  await expect(api.create({ domain: 'second.example' })).rejects.toMatchObject({ failure: { kind: 'limit' } });
});

it('never exposes an API response after logout or replays an uncertain creation', async () => {
  const data: Record<string, unknown> = { session: { instance: 'https://mail.example', email: 'u@example.net', access: 'secret', refresh: 'refresh', expiresAt: Date.now() + 100000 } };
  let resolve!: (response: Response) => void;
  let begin!: () => void;
  const started = new Promise<void>((r) => { begin = r; });
  let posts = 0;
  const deps: AuthDependencies = {
    storage: { get: async (k) => data[k], set: async (k, v) => { data[k] = v; }, remove: async (keys) => { keys.forEach((k) => delete data[k]); } },
    tabs: { create: async () => 1, update: async () => {}, remove: async () => {} }, now: Date.now,
    fetch: async (url, init) => {
      if (String(url).endsWith('/revoke')) return new Response();
      if (init?.method === 'POST') { posts++; throw new TypeError('Offline'); }
      begin(); return new Promise((r) => { resolve = r; });
    },
  };
  const auth = new Auth(deps);
  const api = new Api(auth, deps.fetch, new PreferencesStore(auth, deps.storage), async () => false);
  await expect(api.create({})).rejects.toMatchObject({ failure: { creationUncertain: true } });
  expect(posts).toBe(1);
  const pending = api.aliases('', 1);
  await started;
  await auth.logout();
  resolve(Response.json({ email_aliases: [], page_number: 1, page_size: 20, total_pages: 0, total_entries: 0 }));
  await expect(pending).rejects.toThrow();
});

it('never sends a replacement instance credential to an old request after a delayed 401', async () => {
  const data: Record<string, unknown> = { session: { instance: 'https://old.example', email: 'old@example.net', access: 'old-access', refresh: 'old-refresh', expiresAt: Date.now() + 100000 } };
  const requests: { url: string; authorization: string | null }[] = [];
  let navigation = '';
  let respond!: (response: Response) => void;
  let begin!: () => void;
  const started = new Promise<void>((resolve) => { begin = resolve; });
  const deps: AuthDependencies = {
    storage: { get: async (key) => data[key], set: async (key, value) => { data[key] = value; }, remove: async (keys) => { keys.forEach((key) => delete data[key]); } },
    tabs: { create: async () => 17, update: async (_id, url) => { navigation = url; }, remove: async () => {} },
    now: Date.now,
    fetch: async (input, init) => {
      const url = String(input);
      requests.push({ url, authorization: new Headers(init?.headers).get('Authorization') });
      if (url.endsWith('/oauth/revoke')) return new Response();
      if (url.endsWith('/oauth/token')) return Response.json({ access_token: 'new-instance-access', refresh_token: 'new-refresh', expires_in: 3600, token_type: 'Bearer' });
      if (url.endsWith('/me')) return Response.json({ email: 'new@example.net' });
      if (requests.filter((request) => request.url.includes('/aliases?')).length === 1) {
        begin();
        return new Promise((resolve) => { respond = resolve; });
      }
      return Response.json({ email_aliases: [], page_number: 1, page_size: 20, total_entries: 0, total_pages: 0 });
    },
  };
  const auth = new Auth(deps);
  const api = new Api(auth, deps.fetch, new PreferencesStore(auth, deps.storage), async () => false);
  const pending = api.aliases('', 1);
  await started;
  await auth.login('https://new.example');
  const authorize = new URL(navigation);
  await auth.callback(17, `https://new.example/oauth/extension/callback?${new URLSearchParams({ code: 'new-code', state: authorize.searchParams.get('state')!, iss: 'https://new.example' })}`);
  expect(await auth.identity()).toEqual({ instance: 'https://new.example', email: 'new@example.net' });
  respond(new Response(null, { status: 401 }));
  await expect(pending).rejects.toThrow();
  expect(requests.filter((request) => new URL(request.url).origin === 'https://old.example' && request.authorization === 'Bearer new-instance-access')).toEqual([]);
});
