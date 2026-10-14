import type { Auth } from './auth';
import type { PreferencesStore } from './preferences';
import type { AccountView, Alias, AliasPage, Capabilities, CreateAlias, Failure } from '../shared/contracts';

export class OperationError extends Error {
  constructor(readonly failure: Failure) { super(failure.message); }
}
function invalid(): never { throw new OperationError({ kind: 'unknown', message: 'The server returned an invalid response.' }); }
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  return value as Record<string, unknown>;
}
function string(value: unknown): string { return typeof value === 'string' ? value : invalid(); }
function count(value: unknown): number { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : invalid(); }
function boolean(value: unknown): boolean { return typeof value === 'boolean' ? value : invalid(); }
function alias(value: unknown): Alias {
  const v = object(value);
  if (!Array.isArray(v.blocked_addresses)) return invalid();
  return { address: string(v.address), enabled: boolean(v.enabled),
    title: v.title === null ? null : string(v.title), notes: v.notes === null ? null : string(v.notes),
    forwarded: count(v.forwarded), blocked: count(v.blocked), blocked_addresses: v.blocked_addresses.map(string) };
}
function pagination(v: Record<string, unknown>) {
  return { page_number: count(v.page_number), page_size: count(v.page_size), total_entries: count(v.total_entries), total_pages: count(v.total_pages) };
}
export class Api {
  constructor(private auth: Auth, private fetcher: typeof fetch, private preferences: PreferencesStore, private websitePermission: () => Promise<boolean>) {}
  private async get(path: string, input?: CreateAlias): Promise<unknown> {
    const generation = this.auth.generation;
    const identity = await this.auth.identity();
    if (!identity) throw new OperationError({ kind: 'auth', message: 'Sign in to Shroud.email.' });
    let token: string;
    try { token = await this.auth.accessToken(); } catch { throw new OperationError({ kind: 'auth', message: 'Your session expired. Sign in again.' }); }
    this.auth.assertCurrent(generation);
    const send = (access: string) => this.fetcher(`${identity.instance}/api/v1/${path}`, {
      method: input ? 'POST' : 'GET', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
      ...(input ? { body: JSON.stringify(input) } : {}), credentials: 'omit', cache: 'no-store', signal: AbortSignal.timeout(15000),
    });
    let response: Response;
    try {
      response = await send(token);
      this.auth.assertCurrent(generation);
      if (response.status === 401 && !input) {
        const refreshed = await this.auth.accessToken(true);
        this.auth.assertCurrent(generation);
        response = await send(refreshed);
      }
    } catch {
      this.auth.assertCurrent(generation);
      throw new OperationError({ kind: 'network', message: input ? 'The result is uncertain. Check your aliases before creating another.' : 'Could not reach the server. Try again.', ...(input ? { creationUncertain: true } : {}) });
    }
    this.auth.assertCurrent(generation);
    let value: unknown;
    try { value = await response.json(); } catch {
      throw new OperationError({ kind: 'unknown', message: 'The server returned an invalid response.', ...(input ? { creationUncertain: true } : {}) });
    }
    this.auth.assertCurrent(generation);
    if (!response.ok) {
      const v = object(value);
      const kind = v.code === 'free_limit_reached' ? 'limit' : response.status === 401 ? 'auth' : response.status === 403 || response.status === 422 ? 'validation' : 'unknown';
      throw new OperationError({ kind, message: typeof v.error === 'string' ? v.error : 'The request failed.', ...(input && response.status >= 500 ? { creationUncertain: true } : {}) });
    }
    return value;
  }
  async account(): Promise<AccountView | null> {
    const generation = this.auth.generation;
    const identity = await this.auth.identity();
    if (!identity) return null;
    const v = object(await this.get('alias-capabilities'));
    const capabilities: Capabilities = { alias_count: count(v.alias_count), alias_limit: v.alias_limit === null ? null : count(v.alias_limit), can_create: boolean(v.can_create), default_domain: string(v.default_domain) };
    const domains = [capabilities.default_domain];
    let page = 1;
    let totalPages = 1;
    do {
      const result = object(await this.get(`domains?page=${page}&page_size=100`));
      const paginationData = pagination(result);
      if (!Array.isArray(result.domains) || paginationData.page_number !== page) return invalid();
      domains.push(...result.domains.map((d) => string(object(d).domain)));
      totalPages = paginationData.total_pages;
      page++;
    } while (page <= totalPages);
    const usable = [...new Set(domains)];
    const preferences = await this.preferences.read(usable);
    const websitePermission = await this.websitePermission();
    this.auth.assertCurrent(generation);
    return { ...identity, capabilities, domains: usable, preferences, websitePermission };
  }
  async aliases(search: string, page: number, recent = false): Promise<AliasPage> {
    const params = new URLSearchParams({ search, page: String(recent ? 1 : page), page_size: String(recent ? 3 : 20) });
    if (recent) params.set('enabled', 'true');
    const value = object(await this.get(`aliases?${params}`));
    if (!Array.isArray(value.email_aliases)) return invalid();
    return { ...pagination(value), email_aliases: value.email_aliases.map(alias) };
  }
  async create(input: CreateAlias): Promise<Alias> {
    const value = await this.get('aliases', input);
    try { return alias(value); } catch {
      throw new OperationError({ kind: 'unknown', message: 'The alias may have been created. Refresh your aliases before trying again.', creationUncertain: true });
    }
  }
}
