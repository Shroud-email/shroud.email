import { expect, it } from 'vitest';
import { Auth } from '../../background/auth';
import { PreferencesStore } from '../../background/preferences';

it('isolates preferences by account and falls back when a domain loses verification', async () => {
  const data: Record<string, unknown> = { session: { instance: 'https://mail.example', email: 'first@example.net' } };
  const storage = { get: async (k: string) => data[k], set: async (k: string, v: unknown) => { data[k] = v; }, remove: async (keys: string[]) => { keys.forEach((k) => delete data[k]); } };
  const auth = new Auth({ storage, fetch, now: Date.now, tabs: { create: async () => 1, update: async () => {}, remove: async () => {} } });
  const store = new PreferencesStore(auth, storage);
  await store.update({ selectedDomain: 'custom.example', appearance: 'dark', showIcon: true });
  expect((await store.read(['default.example', 'custom.example'])).selectedDomain).toBe('custom.example');
  expect((await store.read(['default.example'])).selectedDomain).toBe('default.example');
  data.session = { instance: 'https://mail.example', email: 'second@example.net' };
  expect(await store.read(['second.example'])).toEqual({ selectedDomain: 'second.example', appearance: 'system', showIcon: false });
});
