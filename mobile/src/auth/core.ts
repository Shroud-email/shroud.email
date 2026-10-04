export const issuer = 'https://app.shroud.email';
export const resource = `${issuer}/api/v1`;
export const redirectUri = `${issuer}/oauth/callback`;
export type Pending = {
  state: string;
  verifier: string;
  clientId: string;
  created: number;
};
export type Tokens = { access: string; refresh: string; expires: number };
export type Account = { id: string; email: string };
type Store = {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
};

export function callbackCode(
  url: string,
  pending: Pending,
  now: number,
  clientId: string
) {
  const parsed = new URL(url);
  if (
    parsed.origin !== issuer ||
    parsed.pathname !== '/oauth/callback' ||
    parsed.hash ||
    parsed.username ||
    parsed.password
  )
    throw new Error('Invalid callback URL.');
  for (const key of [
    'state',
    'iss',
    'code',
    'error',
    'error_description',
    'access_token',
    'refresh_token',
    'id_token',
  ]) {
    if (parsed.searchParams.getAll(key).length > 1)
      throw new Error('Duplicate callback parameters.');
  }
  if (
    ['access_token', 'refresh_token', 'id_token'].some((key) =>
      parsed.searchParams.has(key)
    )
  )
    throw new Error('Unexpected credentials in callback.');
  if (
    pending.clientId !== clientId ||
    now - pending.created > 10 * 60_000 ||
    now < pending.created ||
    !/^[A-Za-z0-9._~-]{43,128}$/.test(pending.verifier)
  )
    throw new Error('Sign-in expired. Please try again.');
  if (
    !pending.state ||
    parsed.searchParams.get('state') !== pending.state ||
    parsed.searchParams.get('iss') !== issuer
  )
    throw new Error('Invalid callback state or issuer.');
  if (parsed.searchParams.has('error'))
    throw new Error('Authorization was declined.');
  const code = parsed.searchParams.get('code');
  if (!code) throw new Error('Missing authorization code.');
  return code;
}

export class AuthService {
  private queue: Promise<unknown> = Promise.resolve();
  constructor(
    private store: Store,
    private clientId: string,
    private transport: typeof fetch = fetch,
    private now = Date.now
  ) {}
  private async request(url: string, options: RequestInit) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      return await this.transport(url, {
        ...options,
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
  }
  private serial<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation);
    this.queue = result.catch(() => {});
    return result;
  }
  savePending(pending: Pending) {
    return this.serial(() =>
      this.store.set('pending', JSON.stringify(pending))
    );
  }
  cancelPending() {
    return this.serial(() => this.store.remove('pending'));
  }
  private async token(fields: Record<string, string>) {
    const response = await this.request(`${issuer}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        ...fields,
        client_id: this.clientId,
        resource,
      }).toString(),
    });
    if (!response.ok)
      throw new Error('Session unavailable. Please sign in again.');
    const body = await response.json();
    if (
      typeof body.access_token !== 'string' ||
      !body.access_token ||
      typeof body.refresh_token !== 'string' ||
      !body.refresh_token ||
      body.resource !== resource ||
      body.token_type?.toLowerCase() !== 'bearer' ||
      !Number.isFinite(body.expires_in) ||
      body.expires_in <= 0
    )
      throw new Error('Invalid token response.');
    const tokens: Tokens = {
      access: body.access_token,
      refresh: body.refresh_token,
      expires: this.now() + Math.min(body.expires_in, 3600) * 1000,
    };
    await this.store.set('tokens', JSON.stringify(tokens));
    return tokens;
  }
  callback(url: string) {
    return this.serial(async () => {
      const raw = await this.store.get('pending');
      if (!raw) return false; // Already consumed, including the router/browser race.
      const pending: Pending = JSON.parse(raw);
      const code = callbackCode(url, pending, this.now(), this.clientId);
      // Consume before exchange: an ambiguous network failure must never replay a code.
      await this.store.remove('pending');
      await this.token({
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
        code_verifier: pending.verifier,
      });
      return true;
    });
  }
  account(): Promise<Account | null> {
    return this.serial(async () => {
      const raw = await this.store.get('tokens');
      if (!raw) return null;
      let tokens: Tokens = JSON.parse(raw);
      if (tokens.expires <= this.now() + 60_000) {
        // A process death during rotation must not replay the previous refresh token.
        await this.store.remove('tokens');
        try {
          tokens = await this.token({
            grant_type: 'refresh_token',
            refresh_token: tokens.refresh,
          });
        } catch (error) {
          await this.store.remove('tokens');
          throw error;
        }
      }
      const response = await this.request(`${resource}/me`, {
        headers: { Authorization: `Bearer ${tokens.access}` },
      });
      if (!response.ok) {
        if (response.status === 401 || response.status === 403)
          await this.store.remove('tokens');
        throw new Error(
          'Unable to verify your account. Please reconnect or sign in again.'
        );
      }
      const account = await response.json();
      if (typeof account.id !== 'string' || typeof account.email !== 'string')
        throw new Error('Invalid account response.');
      return { id: account.id, email: account.email };
    });
  }
  logout() {
    return this.serial(async () => {
      const raw = await this.store.get('tokens');
      await this.store.remove('tokens');
      await this.store.remove('pending');
      if (!raw) return;
      const tokens: Tokens = JSON.parse(raw);
      try {
        const response = await this.request(`${issuer}/oauth/revoke`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            token: tokens.refresh,
            client_id: this.clientId,
          }).toString(),
        });
        if (!response.ok) throw new Error();
      } catch {
        throw new Error(
          'Signed out locally, but the connection could not be revoked. Revoke it in Shroud account settings when online.'
        );
      }
    });
  }
}
