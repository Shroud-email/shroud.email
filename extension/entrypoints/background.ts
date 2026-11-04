import { defineBackground } from "wxt/utils/define-background";
import { browser } from "wxt/browser";
import { Auth } from "../background/auth";
import { Api } from "../background/api";
import { PreferencesStore } from "../background/preferences";
import { messageHandler } from "../background/messages";
import { WEBSITE_ORIGINS, instancePattern } from "../shared/permissions";

export default defineBackground(() => {
  const storage = {
    get: async (key: string) => (await browser.storage.local.get(key))[key],
    set: async (key: string, value: unknown) => {
      await browser.storage.local.set({ [key]: value });
    },
    remove: async (keys: string[]) => {
      await browser.storage.local.remove(keys);
    },
  };
  const auth = new Auth({
    storage,
    tabs: {
      create: async () => {
        const tab = await browser.tabs.create({ url: "about:blank" });
        if (tab.id === undefined) throw new Error("Could not open sign-in tab");
        return tab.id;
      },
      update: async (id, url) => {
        await browser.tabs.update(id, { url });
      },
      remove: async (id) => {
        await browser.tabs.remove(id);
      },
    },
    fetch: fetch.bind(globalThis),
    now: Date.now,
  });
  const preferences = new PreferencesStore(auth, storage);
  const websitePermission = () =>
    browser.permissions.contains({ origins: WEBSITE_ORIGINS });
  const api = new Api(
    auth,
    fetch.bind(globalThis),
    preferences,
    websitePermission,
  );
  let injectionUpdates: Promise<void> = Promise.resolve();
  function updateInjection(): Promise<void> {
    const next = injectionUpdates.then(async () => {
      const enabled =
        (await preferences.read()).showIcon && (await websitePermission());
      const registered = await browser.scripting.getRegisteredContentScripts({
        ids: ["email-fields"],
      });
      if (enabled && !registered.length) {
        await browser.scripting.registerContentScripts([
          {
            id: "email-fields",
            matches: WEBSITE_ORIGINS,
            js: ["content-scripts/email-fields.js"],
            allFrames: true,
            runAt: "document_idle",
            persistAcrossSessions: true,
          },
        ]);
      } else if (!enabled && registered.length) {
        await browser.scripting.unregisterContentScripts({
          ids: ["email-fields"],
        });
      }
      for (const tab of await browser.tabs.query({})) {
        if (tab.id === undefined || !tab.url || !/^https?:/.test(tab.url))
          continue;
        if (enabled) {
          await browser.scripting
            .executeScript({
              target: { tabId: tab.id, allFrames: true },
              files: ["/content-scripts/email-fields.js"],
            })
            .catch(() => {});
        } else {
          await browser.tabs
            .sendMessage(tab.id, { type: "injection-state", enabled: false })
            .catch(() => {});
        }
      }
    });
    injectionUpdates = next.catch(() => {});
    return next;
  }
  const handle = messageHandler({
    auth,
    api,
    preferences,
    extensionId: browser.runtime.id,
    popupUrl: browser.runtime.getURL("/popup.html"),
    instanceAllowed: (instance) =>
      browser.permissions.contains({ origins: [instancePattern(instance)] }),
    contentAllowed: async (sender) => {
      if (!sender.url || !/^https?:\/\//.test(sender.url)) return false;
      return (
        (await preferences.read()).showIcon &&
        (await websitePermission()) &&
        (await browser.permissions.contains({
          origins: [instancePattern(new URL(sender.url).origin)],
        }))
      );
    },
    open: async (url) => {
      await browser.tabs.create({ url });
    },
    updateInjection,
  });
  browser.runtime.onMessage.addListener((message, sender) =>
    handle(message, sender),
  );
  browser.tabs.onUpdated.addListener((id, change) => {
    if (change.url) void auth.callback(id, change.url).catch(() => {});
  });
  browser.tabs.onRemoved.addListener((id) => {
    void auth.cancel(id).catch(() => {});
  });
  if ("setAccessLevel" in browser.storage.local) {
    void browser.storage.local
      .setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" })
      .catch(() => {});
  }
  browser.permissions.onAdded.addListener(() => {
    void updateInjection().catch(() => {});
  });
  browser.permissions.onRemoved.addListener(() => {
    void updateInjection().catch(() => {});
  });
  browser.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !changes.session) return;
    const { oldValue, newValue } = changes.session;
    const previous = oldValue as
      { email?: string; instance?: string } | undefined;
    const next = newValue as { email?: string; instance?: string } | undefined;
    if (
      previous?.email !== next?.email ||
      previous?.instance !== next?.instance
    ) {
      void browser.runtime
        .sendMessage({ type: "account-changed" })
        .catch(() => {});
      void updateInjection().catch(() => {});
    }
  });
  void updateInjection().catch(() => {});
});
