import { defineBackground } from 'wxt/utils/define-background';
import { browser } from 'wxt/browser';
import { Auth } from '../background/auth';

export default defineBackground(() => {
  const auth = new Auth({
    storage: {
      get: async (key) => (await browser.storage.local.get(key))[key],
      set: async (key, value) => { await browser.storage.local.set({ [key]: value }); },
      remove: async (keys) => { await browser.storage.local.remove(keys); },
    },
    tabs: {
      create: async () => {
        const tab = await browser.tabs.create({ url: 'about:blank' });
        if (tab.id === undefined) throw new Error('Could not open sign-in tab');
        return tab.id;
      },
      update: async (id, url) => { await browser.tabs.update(id, { url }); },
      remove: async (id) => { await browser.tabs.remove(id); },
    },
    fetch: fetch.bind(globalThis), now: Date.now,
  });
  browser.tabs.onUpdated.addListener((id, change) => {
    if (change.url) void auth.callback(id, change.url).catch(() => {});
  });
  browser.tabs.onRemoved.addListener((id) => { void auth.cancel(id).catch(() => {}); });
  if ('setAccessLevel' in browser.storage.local) {
    void browser.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' }).catch(() => {});
  }
});
