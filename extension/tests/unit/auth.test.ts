import { describe, expect, it } from 'vitest';
import { Auth, challenge, type AuthDependencies } from '../../background/auth';

function fixture() {
  const data: Record<string, unknown> = {};
  const navigations: string[] = [];
  const closed: number[] = [];
  const requests: { url: string; body: URLSearchParams }[] = [];
  let response: (() => Promise<Response>) | undefined;
  const deps: AuthDependencies = {
    storage: {
      get: async (key) => structuredClone(data[key]),
      set: async (key, value) => { data[key] = structuredClone(value); },
      remove: async (keys) => { keys.forEach((key) => delete data[key]); },
    },
    tabs: {
      create: async () => 17,
      update: async (_id, url) => { navigations.push(url); },
      remove: async (id) => { closed.push(id); },
    },
    now: () => 1000000,
    fetch: async (url, init) => {
      requests.push({ url: String(url), body: new URLSearchParams(String(init?.body ?? '')) });
      if (String(url).endsWith('/me')) return Response.json({ email: 'user@example.net' });
      return response ? response() : Response.json({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600, token_type: 'Bearer' });
    },
  };
  const auth = new Auth(deps);
  const callback = () => {
    const authorize = new URL(navigations[0]!);
    return `https://mail.example/oauth/extension/callback?${new URLSearchParams({ code: 'one-use', state: authorize.searchParams.get('state')!, iss: 'https://mail.example' })}`;
  };
  return { auth, deps, data, navigations, closed, requests, callback, respond: (fn: () => Promise<Response>) => { response = fn; } };
}

describe('OAuth lifecycle', () => {
  it('uses the independent RFC 7636 S256 vector', async () => {
    expect(await challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')).toBe('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });
  it('survives background restart and consumes the exact callback once', async () => {
    const f = fixture();
    await f.auth.login('https://mail.example');
    const url = new URL(f.navigations[0]!);
    expect(url.searchParams.get('client_id')).toBe('fc4258c1-58a9-4865-8f2f-e78345dcfd46');
    expect(url.searchParams.get('resource')).toBe('https://mail.example/api/v1');
    const resumed = new Auth(f.deps);
    await Promise.all([resumed.callback(17, f.callback()), resumed.callback(17, f.callback())]);
    expect(await resumed.identity()).toEqual({ instance: 'https://mail.example', email: 'user@example.net' });
    expect(f.requests.filter((r) => r.url.endsWith('/token'))).toHaveLength(1);
    expect(f.requests[0]!.body.get('code')).toBe('one-use');
    expect(f.navigations.at(-1)).toBe('https://mail.example/oauth/extension/callback');
    expect(f.closed).toEqual([17]);
  });
  it.each(['tab', 'state', 'iss', 'path', 'origin', 'credentials', 'fragment', 'duplicate', 'both', 'expired'])('rejects %s without exchanging', async (bad) => {
    const f = fixture();
    await f.auth.login('https://mail.example');
    const url = new URL(f.callback());
    if (bad === 'state' || bad === 'iss') url.searchParams.set(bad, 'wrong');
    if (bad === 'path') url.pathname += '/extra';
    if (bad === 'origin') url.hostname = 'evil.example';
    if (bad === 'credentials') url.username = 'attacker';
    if (bad === 'fragment') url.hash = 'secret';
    if (bad === 'duplicate') url.searchParams.append('code', 'second');
    if (bad === 'both') url.searchParams.set('error', 'access_denied');
    if (bad === 'expired') f.deps.now = () => 2000000;
    await f.auth.callback(bad === 'tab' ? 99 : 17, url.href);
    expect(await f.auth.identity()).toBeNull();
    expect(f.requests).toEqual([]);
    expect(f.closed).toEqual([]);
  });
  it('cancels only the pending authorization tab', async () => {
    const f = fixture();
    await f.auth.login('https://mail.example');
    await f.auth.cancel(99);
    await f.auth.cancel(17);
    await f.auth.callback(17, f.callback());
    expect(f.requests).toEqual([]);
  });
  it('serializes refresh rotation, and logout cannot be undone by its response', async () => {
    const f = fixture();
    await f.auth.login('https://mail.example');
    await f.auth.callback(17, f.callback());
    f.deps.now = () => 5000000;
    let resolve!: (r: Response) => void;
    let started!: () => void;
    const ready = new Promise<void>((r) => { started = r; });
    f.respond(() => { started(); return new Promise((r) => { resolve = r; }); });
    const pending = Promise.all([f.auth.accessToken(), f.auth.accessToken()]);
    await ready;
    resolve(Response.json({ access_token: 'new-access', refresh_token: 'new-refresh', expires_in: 3600, token_type: 'Bearer' }));
    expect(await pending).toEqual(['new-access', 'new-access']);
    expect(f.requests.filter((r) => r.body.get('grant_type') === 'refresh_token')).toHaveLength(1);
    f.deps.now = () => 10000000;
    const delayed = f.auth.accessToken();
    await ready;
    // Wait until this refresh has actually entered its deferred transport.
    while (f.requests.filter((r) => r.body.get('grant_type') === 'refresh_token').length < 2) await Promise.resolve();
    const logout = f.auth.logout();
    resolve(Response.json({ access_token: 'late', refresh_token: 'late-refresh', expires_in: 3600, token_type: 'Bearer' }));
    await expect(delayed).rejects.toThrow();
    // Revocation is best-effort; release its transport too.
    f.respond(async () => new Response(null, { status: 200 }));
    await logout;
    expect(await f.auth.identity()).toBeNull();
    expect(f.data).toEqual({});
  });
});
