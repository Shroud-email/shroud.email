export type Alias = {
  address: string; enabled: boolean; title: string | null; notes: string | null;
  forwarded: number; blocked: number; blocked_addresses: string[];
};
export type AliasPage = {
  email_aliases: Alias[]; page_number: number; page_size: number;
  total_entries: number; total_pages: number;
};
export type Capabilities = {
  alias_count: number; alias_limit: number | null; can_create: boolean; default_domain: string;
};
export type CreateAlias = { title?: string; domain?: string; local_part?: string };
export type Appearance = 'system' | 'light' | 'dark';
export type Preferences = { appearance: Appearance; showIcon: boolean; selectedDomain: string };
export type AccountView = {
  instance: string; email: string; capabilities: Capabilities; domains: string[];
  preferences: Preferences; websitePermission: boolean;
};
export type Failure = {
  kind: 'auth' | 'limit' | 'validation' | 'network' | 'permission' | 'unknown';
  message: string; creationUncertain?: boolean;
};
export type Reply<T> = { ok: true; value: T } | { ok: false; error: Failure };
export type Message =
  | { type: 'account' }
  | { type: 'aliases'; search: string; page: number; recent?: boolean }
  | { type: 'create'; input: CreateAlias }
  | { type: 'login'; instance: string }
  | { type: 'logout' }
  | { type: 'preferences'; patch: Partial<Preferences> }
  | { type: 'selected-domain'; domain: string }
  | { type: 'open'; destination: 'signup' | 'billing'; instance?: string };

export type Result<M extends Message> = M['type'] extends 'account' ? AccountView | null : M['type'] extends 'aliases' ? AliasPage : M['type'] extends 'create' ? Alias : void;
export async function request<M extends Message>(message: M): Promise<Reply<Result<M>>> {
  const { browser } = await import('wxt/browser');
  return browser.runtime.sendMessage(message);
}
