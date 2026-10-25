<script setup lang="ts">
import { ref } from "vue";
import { browser } from "wxt/browser";
import {
  request,
  type AccountView,
  type Appearance,
  type Preferences,
} from "../shared/contracts";
import { WEBSITE_ORIGINS } from "../shared/permissions";
const props = defineProps<{
  account: AccountView | null;
  appearance: Appearance;
}>();
const emit = defineEmits<{
  back: [];
  refresh: [];
  logout: [];
  appearance: [value: Appearance];
}>();
const busy = ref(false);
const error = ref("");
async function save(patch: Partial<Preferences>) {
  if (busy.value) return;
  if (!props.account) {
    if (patch.appearance) emit("appearance", patch.appearance);
    return;
  }
  busy.value = true;
  error.value = "";
  try {
    const result = await request({ type: "preferences", patch });
    if (!result.ok) error.value = result.error.message;
    else emit("refresh");
  } catch {
    error.value = "Could not save settings. Try again.";
  } finally {
    busy.value = false;
  }
}
async function allow() {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    if (await browser.permissions.request({ origins: WEBSITE_ORIGINS }))
      emit("refresh");
    else error.value = "Website access was not allowed.";
  } catch {
    error.value = "Could not request website access.";
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section
    class="screen settings flex flex-col gap-4"
    :class="{ 'permission-missing': account && !account.websitePermission }"
  >
    <header class="flex h-8 items-center">
      <button class="back" @click="$emit('back')">‹ Settings</button>
    </header>
    <template v-if="account"
      ><p class="muted tracking-wider">EMAIL FIELD SHORTCUT</p>
      <div class="toggle-row flex items-center justify-between gap-3">
        <strong>Show icon in email fields</strong
        ><button
          role="switch"
          aria-label="Show icon in email fields"
          :aria-checked="account.preferences.showIcon"
          class="toggle"
          :disabled="busy"
          @click="save({ showIcon: !account.preferences.showIcon })"
        >
          <span />
        </button>
      </div>
      <button
        v-if="!account.websitePermission"
        class="primary"
        :disabled="busy"
        @click="allow"
      >
        Allow website access
      </button></template
    >
    <div class="flex flex-col gap-2">
      <p>Appearance</p>
      <div
        class="segments appearance flex"
        role="group"
        aria-label="Appearance"
      >
        <button
          v-for="option in ['system', 'light', 'dark'] as const"
          :key="option"
          :aria-pressed="appearance === option"
          :disabled="busy"
          @click="save({ appearance: option })"
        >
          {{ option.charAt(0).toUpperCase() + option.slice(1) }}
        </button>
      </div>
    </div>
    <div v-if="account" class="account-footer flex flex-col gap-2">
      <p class="muted break-words">Signed in as {{ account.email }}</p>
      <button class="logout text-left" @click="$emit('logout')">Logout</button>
    </div>
    <p v-if="error" role="alert" class="failure">{{ error }}</p>
  </section>
</template>
