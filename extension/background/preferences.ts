import type { Auth, AuthDependencies } from './auth';
import type { Preferences } from '../shared/contracts';

export class PreferencesStore {
  constructor(private auth: Auth, private storage: AuthDependencies['storage']) {}
  async read(domains: string[] = []): Promise<Preferences> {
    const generation = this.auth.generation;
    const identity = await this.auth.identity();
    const saved = await this.storage.get('preferences') as { account: string; value: Preferences } | undefined;
    this.auth.assertCurrent(generation);
    const account = identity ? `${identity.instance}\n${identity.email}` : '';
    const value = saved?.account === account ? saved.value : { appearance: 'system' as const, showIcon: false, selectedDomain: '' };
    return { ...value, selectedDomain: domains.length && !domains.includes(value.selectedDomain) ? domains[0]! : value.selectedDomain };
  }
  async update(patch: Partial<Preferences>): Promise<void> {
    const generation = this.auth.generation;
    const identity = await this.auth.identity();
    if (!identity) throw new Error('Sign in to change preferences');
    const account = `${identity.instance}\n${identity.email}`;
    await this.auth.commit(generation, async () => {
      const saved = await this.storage.get('preferences') as { account: string; value: Preferences } | undefined;
      const value = saved?.account === account ? saved.value : { appearance: 'system', showIcon: false, selectedDomain: '' };
      await this.storage.set('preferences', { account, value: { ...value, ...patch } });
    });
  }
}
