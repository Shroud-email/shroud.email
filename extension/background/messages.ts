import type { Message, Reply } from '../shared/contracts';
import type { Auth } from './auth';
import { Api, OperationError } from './api';
import type { PreferencesStore } from './preferences';
import { normalizeInstance } from '../shared/instance';

function shape(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some((k) => !keys.includes(k))) throw new Error('Invalid message');
  return value as Record<string, unknown>;
}
function text(value: unknown, max = 1024): boolean { return typeof value === 'string' && value.length <= max; }
export function validateMessage(value: unknown): Message {
  const type = shape(value, ['type', 'search', 'page', 'recent', 'input', 'instance', 'patch', 'destination', 'domain']).type;
  let valid = false;
  switch (type) {
    case 'account': case 'logout': shape(value, ['type']); valid = true; break;
    case 'login': { const v = shape(value, ['type', 'instance']); valid = text(v.instance) && normalizeInstance(v.instance as string) === v.instance; break; }
    case 'aliases': { const v = shape(value, ['type', 'search', 'page', 'recent']); valid = text(v.search) && Number.isSafeInteger(v.page) && Number(v.page) > 0 && (v.recent === undefined || typeof v.recent === 'boolean'); break; }
    case 'create': {
      const v = shape(value, ['type', 'input']); const input = shape(v.input, ['title', 'domain', 'local_part']);
      valid = Object.values(input).every((v) => text(v)) && (input.local_part === undefined || (typeof input.domain === 'string' && !!input.domain && !!input.local_part)); break;
    }
    case 'selected-domain': { const v = shape(value, ['type', 'domain']); valid = text(v.domain, 253) && !!v.domain; break; }
    case 'preferences': {
      const v = shape(value, ['type', 'patch']); const patch = shape(v.patch, ['appearance', 'showIcon', 'selectedDomain']);
      valid = (patch.appearance === undefined || ['system', 'light', 'dark'].includes(String(patch.appearance))) && (patch.showIcon === undefined || typeof patch.showIcon === 'boolean') && (patch.selectedDomain === undefined || text(patch.selectedDomain, 253)); break;
    }
    case 'open': { const v = shape(value, ['type', 'destination', 'instance']); valid = ['signup', 'billing'].includes(String(v.destination)) && (v.instance === undefined || (text(v.instance) && normalizeInstance(v.instance as string) === v.instance)) && !(v.destination === 'billing' && v.instance !== undefined); break; }
  }
  if (!valid) throw new Error('Invalid message');
  return value as Message;
}
export type Sender = { id?: string; url?: string; tab?: { id?: number }; frameId?: number };
type MessageDependencies = {
  auth: Auth; api: Api; preferences: PreferencesStore; extensionId: string; popupUrl: string;
  contentAllowed(sender: Sender): Promise<boolean>;
  instanceAllowed(instance: string): Promise<boolean>;
  open(url: string): Promise<void>;
  updateInjection(): Promise<void>;
};
export function messageHandler(deps: MessageDependencies) {
  return async (raw: unknown, sender: Sender): Promise<Reply<unknown>> => {
    try {
      const generation = deps.auth.generation;
      const message = validateMessage(raw);
      const popup = sender.id === deps.extensionId && sender.url === deps.popupUrl;
      const content = sender.id === deps.extensionId && Number.isInteger(sender.tab?.id) && Number.isInteger(sender.frameId) && sender.frameId! >= 0 && !!sender.url && await deps.contentAllowed(sender);
      if (!popup && (!content || !['account', 'aliases', 'create', 'selected-domain', 'open'].includes(message.type) || (message.type === 'open' && message.destination !== 'billing'))) {
        throw new OperationError({ kind: 'permission', message: 'This operation is not allowed here.' });
      }
      deps.auth.assertCurrent(generation);
      let value: unknown;
      switch (message.type) {
        case 'account': value = await deps.api.account(); break;
        case 'aliases': value = await deps.api.aliases(message.search, message.page, message.recent); break;
        case 'create': value = await deps.api.create(message.input); break;
        case 'login':
          if (!await deps.instanceAllowed(message.instance)) throw new OperationError({ kind: 'permission', message: 'Allow access to the selected server first.' });
          deps.auth.assertCurrent(generation);
          await deps.auth.login(message.instance); break;
        case 'logout': await deps.auth.logout(); await deps.updateInjection(); break;
        case 'preferences': {
          if (message.patch.selectedDomain !== undefined) {
            const account = await deps.api.account();
            if (!account?.domains.includes(message.patch.selectedDomain)) throw new Error('Domain is not available');
          }
          deps.auth.assertCurrent(generation);
          await deps.preferences.update(message.patch); await deps.updateInjection(); break;
        }
        case 'selected-domain': {
          const account = await deps.api.account();
          if (!account?.domains.includes(message.domain)) throw new Error('Domain is not available');
          deps.auth.assertCurrent(generation);
          await deps.preferences.update({ selectedDomain: message.domain }); break;
        }
        case 'open': {
          const identity = await deps.auth.identity();
          deps.auth.assertCurrent(generation);
          const instance = message.destination === 'billing' ? identity?.instance : message.instance ?? 'https://app.shroud.email';
          if (!instance) throw new OperationError({ kind: 'auth', message: 'Sign in first.' });
          await deps.open(`${instance}${message.destination === 'billing' ? '/settings/billing' : '/users/register'}`); break;
        }
      }
      return { ok: true, value };
    } catch (error) {
      return { ok: false, error: error instanceof OperationError ? error.failure : { kind: 'validation', message: error instanceof Error ? error.message : 'The request failed.' } };
    }
  };
}
