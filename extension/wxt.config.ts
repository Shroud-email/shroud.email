import { defineConfig } from "wxt";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  modules: ["@wxt-dev/module-vue"],
  manifestVersion: 3,
  vite: () => ({ plugins: [tailwindcss()] }),
  manifest: {
    name: "Shroud.email",
    description: "Create and fill private email aliases with Shroud.email.",
    icons: {
      16: "icons/16.png",
      32: "icons/32.png",
      48: "icons/48.png",
      128: "icons/128.png",
    },
    permissions: ["storage", "tabs", "scripting", "clipboardWrite"],
    optional_host_permissions: ["https://*/*", "http://*/*"],
    web_accessible_resources: [
      {
        resources: ["fonts/Inter.var.woff2"],
        matches: ["https://*/*", "http://*/*"],
      },
    ],
    content_security_policy: {
      extension_pages: "script-src 'self'; object-src 'none'",
    },
    browser_specific_settings: {
      gecko: {
        id: "extension@shroud.email",
        strict_min_version: "140.0",
        data_collection_permissions: {
          required: ["authenticationInfo", "personallyIdentifyingInfo"],
        },
      },
    },
  },
});
