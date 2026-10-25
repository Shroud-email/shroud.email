<script setup lang="ts">
import { ref } from "vue";
import { browser } from "wxt/browser";
import { request } from "../shared/contracts";
import { normalizeInstance } from "../shared/instance";
import { instancePattern } from "../shared/permissions";
import Icon from "./Icon.vue";
defineEmits<{ settings: [] }>();
const instance = ref("https://app.shroud.email");
const expanded = ref(false);
const busy = ref(false);
const message = ref("");
async function act(login: boolean) {
  if (busy.value) return;
  busy.value = true;
  message.value = "";
  try {
    const origin = normalizeInstance(instance.value);
    if (
      login &&
      !(await browser.permissions.request({
        origins: [instancePattern(origin)],
      }))
    ) {
      message.value = "Server access was not allowed.";
      return;
    }
    const result = await request(
      login
        ? { type: "login", instance: origin }
        : { type: "open", destination: "signup", instance: origin },
    );
    message.value = result.ok
      ? login
        ? "Finish signing in in the browser tab."
        : ""
      : result.error.message;
  } catch (error) {
    message.value =
      error instanceof Error ? error.message : "Could not sign in. Try again.";
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section class="screen login flex flex-col gap-4" :class="{ expanded }">
    <header class="flex h-8 items-center justify-between">
      <h1>Shroud.email</h1>
      <button
        aria-label="Settings"
        class="icon-button"
        @click="$emit('settings')"
      >
        <Icon name="settings" />
      </button>
    </header>
    <button class="primary" :disabled="busy" @click="act(true)">
      Sign in ↗
    </button>
    <div class="login-signup">
      <button class="link" :disabled="busy" @click="act(false)">
        Create account ↗
      </button>
    </div>
    <button
      class="server-disclosure"
      :aria-expanded="expanded"
      aria-controls="server-url"
      @click="expanded = !expanded"
    >
      Server URL {{ expanded ? "⌃" : "⌄" }}
    </button>
    <input
      v-if="expanded"
      id="server-url"
      v-model="instance"
      type="url"
      aria-label="Server URL"
      autocomplete="url"
      spellcheck="false"
    />
    <p v-if="message" role="status" class="muted">{{ message }}</p>
  </section>
</template>
