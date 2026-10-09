import { normalizeInstance } from '../shared/instance';

export type AuthDependencies = {
  storage: { get(key: string): Promise<unknown>; set(key: string, value: unknown): Promise<void>; remove(keys: string[]): Promise<void> };
  tabs: { create(): Promise<number>; update(id: number, url: string): Promise<void>; remove(id: number): Promise<void> };
  fetch: typeof fetch;
  now(): number;
};
const CLIENT = 'fc4258c1-58a9-4865-8f2f-e78345dcfd46';
const SCOPES = 'profile:read aliases:read aliases:create domains:read';
type Pending = { instance: string; verifier: string; state: string; createdAt: number; tabId: number };
type Session = { instance: string; email: string; access: string; refresh: string; expiresAt: number };
function base64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
export async function challenge(verifier: string): Promise<string> {
  return base64(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
}
function random(): string { return base64(crypto.getRandomValues(new Uint8Array(32))); }

export class Auth {
  generation = 0;
  private writes: Promise<unknown> = Promise.resolve();
  private exchange: Promise<void> = Promise.resolve();
  private refreshing: Promise<string> | null = null;
  constructor(private deps: AuthDependencies) {}

  assertCurrent(generation: number): void {
    if (generation !== this.generation) throw new Error('Account changed. Sign in again.');
  }
  // Serial writes let logout remove data after any already-started storage write.
  async commit(generation: number, write: () => Promise<void>): Promise<void> {
    const next = this.writes.then(() => { this.assertCurrent(generation); return write(); });
    this.writes = next.catch(() => {});
    await next;
    this.assertCurrent(generation);
  }
  private async session(): Promise<Session | null> {
    await this.writes;
    return (await this.deps.storage.get('session') as Session | undefined) ?? null;
  }
  async identity(): Promise<{ instance: string; email: string } | null> {
    const generation = this.generation;
    const session = await this.session();
    this.assertCurrent(generation);
    return session ? { instance: session.instance, email: session.email } : null;
  }
  async login(input: string): Promise<void> {
    const instance = normalizeInstance(input);
    await this.logout();
    const generation = this.generation;
    const verifier = random();
    const state = random();
    const codeChallenge = await challenge(verifier);
    this.assertCurrent(generation);
    const tabId = await this.deps.tabs.create();
    try {
      const pending: Pending = { instance, verifier, state, createdAt: this.deps.now(), tabId };
      await this.commit(generation, () => this.deps.storage.set('pending', pending));
      const params = new URLSearchParams({ client_id: CLIENT, response_type: 'code',
        redirect_uri: `${instance}/oauth/extension/callback`, resource: `${instance}/api/v1`,
        scope: SCOPES, state, code_challenge: codeChallenge, code_challenge_method: 'S256' });
      await this.deps.tabs.update(tabId, `${instance}/oauth/authorize?${params}`);
    } catch (error) {
      await this.cancel(tabId);
      await this.deps.tabs.remove(tabId).catch(() => {});
      throw error;
    }
  }
  async cancel(tabId: number): Promise<void> {
    const generation = this.generation;
    await this.commit(generation, async () => {
      const pending = await this.deps.storage.get('pending') as Pending | undefined;
      if (pending?.tabId === tabId) await this.deps.storage.remove(['pending']);
    });
  }
  callback(tabId: number, raw: string): Promise<void> {
    const next = this.exchange.then(() => this.consume(tabId, raw));
    this.exchange = next.catch(() => {});
    return next;
  }
  private async consume(tabId: number, raw: string): Promise<void> {
    const generation = this.generation;
    await this.writes;
    const pending = await this.deps.storage.get('pending') as Pending | undefined;
    if (!pending || pending.tabId !== tabId) return;
    const age = this.deps.now() - pending.createdAt;
    let url: URL;
    try { url = new URL(raw); } catch { return; }
    if (age < 0 || age > 300000 || url.origin !== pending.instance ||
      url.pathname !== '/oauth/extension/callback' || url.username || url.password ||
      raw.includes('#') || url.searchParams.get('state') !== pending.state ||
      url.searchParams.get('iss') !== pending.instance) return;
    for (const key of url.searchParams.keys()) if (url.searchParams.getAll(key).length !== 1) return;
    const code = url.searchParams.get('code');
    const error = url.searchParams.get('error');
    if ((!code && !error) || (code && error)) return;
    await this.commit(generation, () => this.deps.storage.remove(['pending']));
    // Once consumed, never reuse the authorization code, even after an uncertain exchange.
    await this.deps.tabs.update(tabId, `${pending.instance}/oauth/extension/callback`).catch(() => {});
    try {
      if (error) return;
      const session = await this.tokens(pending.instance, {
        grant_type: 'authorization_code', code: code!, code_verifier: pending.verifier,
        redirect_uri: `${pending.instance}/oauth/extension/callback`,
      });
      this.assertCurrent(generation);
      const response = await this.deps.fetch(`${pending.instance}/api/v1/me`, {
        headers: { Authorization: `Bearer ${session.access}` }, credentials: 'omit', cache: 'no-store',
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new Error('Sign in again.');
      const profile: unknown = await response.json();
      if (!profile || typeof profile !== 'object' || !('email' in profile) || typeof profile.email !== 'string') throw new Error('Invalid account response');
      session.email = profile.email;
      await this.commit(generation, () => this.deps.storage.set('session', session));
    } finally { await this.deps.tabs.remove(tabId).catch(() => {}); }
  }
  private async tokens(instance: string, fields: Record<string, string>): Promise<Session> {
    const response = await this.deps.fetch(`${instance}/oauth/token`, {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ ...fields, client_id: CLIENT, resource: `${instance}/api/v1` }),
      credentials: 'omit', cache: 'no-store', signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error('Sign in again.');
    const value = await response.json();
    if (typeof value.access_token !== 'string' || typeof value.refresh_token !== 'string' ||
      typeof value.expires_in !== 'number' || value.expires_in <= 0 || !Number.isFinite(value.expires_in) ||
      String(value.token_type).toLowerCase() !== 'bearer') throw new Error('Invalid token response');
    return { instance, email: '', access: value.access_token, refresh: value.refresh_token,
      expiresAt: this.deps.now() + value.expires_in * 1000 };
  }
  accessToken(): Promise<string> {
    if (this.refreshing) return this.refreshing;
    const generation = this.generation;
    const next = this.loadAccess(generation);
    this.refreshing = next;
    void next.finally(() => { if (this.refreshing === next) this.refreshing = null; }).catch(() => {});
    return next;
  }
  private async loadAccess(generation: number): Promise<string> {
    const session = await this.session();
    this.assertCurrent(generation);
    if (!session) throw new Error('Sign in to Shroud.email.');
    if (!session.refresh) {
      await this.commit(generation, () => this.deps.storage.remove(['session', 'preferences']));
      throw new Error('Sign in again.');
    }
    if (session.expiresAt > this.deps.now() + 30000) return session.access;
    // Persist removal before rotation: a suspended worker cannot reuse a consumed refresh token.
    await this.commit(generation, () => this.deps.storage.set('session', { ...session, refresh: '' }));
    try {
      const successor = await this.tokens(session.instance, { grant_type: 'refresh_token', refresh_token: session.refresh });
      successor.email = session.email;
      await this.commit(generation, () => this.deps.storage.set('session', successor));
      return successor.access;
    } catch (error) {
      if (generation === this.generation) {
        await this.commit(generation, () => this.deps.storage.remove(['session', 'preferences']));
      }
      throw error;
    }
  }
  async logout(): Promise<void> {
    const generation = ++this.generation;
    this.refreshing = null;
    const session = await this.session();
    await this.commit(generation, () => this.deps.storage.remove(['session', 'pending', 'preferences']));
    if (session) {
      void this.deps.fetch(`${session.instance}/oauth/revoke`, {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: session.refresh || session.access, client_id: CLIENT }), credentials: 'omit',
        signal: AbortSignal.timeout(5000),
      }).catch(() => {});
    }
  }
}
