import { defineConfig } from 'wxt';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  modules: ['@wxt-dev/module-vue'],
  manifestVersion: 3,
  vite: () => ({ plugins: [tailwindcss()] }),
  manifest: {
    name: 'Shroud.email',
    description: 'Create and fill private email aliases with Shroud.email.',
    permissions: ['storage', 'tabs', 'scripting', 'clipboardWrite'],
    optional_host_permissions: ['https://*/*', 'http://*/*'],
    content_security_policy: { extension_pages: "script-src 'self'; object-src 'none'" },
    browser_specific_settings: { gecko: { id: 'extension@shroud.email' } },
  },
});
