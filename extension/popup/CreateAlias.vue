<script setup lang="ts">
import { ref, watch } from "vue";
import type {
  AccountView,
  Alias,
  CreateAlias,
  Failure,
} from "../shared/contracts";
import LimitNotice from "./LimitNotice.vue";
const props = defineProps<{
  account: AccountView;
  busy: boolean;
  created: Alias | null;
  error: Failure | null;
}>();
const emit = defineEmits<{
  back: [];
  create: [input: CreateAlias];
  copy: [address: string];
  check: [];
  error: [message: string];
}>();
const custom = ref(false);
const localPart = ref("");
const description = ref("");
const domain = ref(props.account.preferences.selectedDomain);
const editing = ref(false);
watch(
  () => props.error,
  () => {
    editing.value = false;
  },
);
function submit() {
  emit("create", {
    domain: domain.value,
    ...(description.value ? { title: description.value } : {}),
    ...(custom.value ? { local_part: localPart.value } : {}),
  });
}
</script>
<template>
  <section
    class="screen create flex flex-col gap-4"
    :class="{
      'at-limit': !account.capabilities.can_create,
      failed: error && error.kind !== 'limit' && !editing,
    }"
  >
    <header class="flex h-8 items-center">
      <button class="back" :disabled="busy" @click="$emit('back')">
        ‹ Create alias
      </button>
    </header>
    <LimitNotice
      :capabilities="account.capabilities"
      @error="$emit('error', $event)"
    />
    <template v-if="created"
      ><div class="flex flex-col gap-2">
        <strong>Alias created</strong>
        <p class="break-all">{{ created.address }}</p>
        <p class="muted">Couldn’t copy automatically. Try Copy below.</p>
      </div>
      <button class="primary" @click="$emit('copy', created.address)">
        Copy
      </button></template
    >
    <form v-else class="flex flex-col gap-4" @submit.prevent="submit">
      <div
        v-if="error && error.kind !== 'limit' && !editing"
        class="failure flex flex-col gap-2.5"
        role="alert"
      >
        <strong>{{
          error.creationUncertain
            ? "Creation result uncertain"
            : "Couldn’t create alias"
        }}</strong>
        <p>{{ error.message }}</p>
      </div>
      <template v-if="!error || error.kind === 'limit' || editing">
        <div class="segments flex" role="group" aria-label="Address type">
          <button type="button" :aria-pressed="!custom" @click="custom = false">
            Random address</button
          ><button type="button" :aria-pressed="custom" @click="custom = true">
            Custom name
          </button>
        </div>
        <label v-if="custom" class="flex flex-col gap-2"
          >Custom name<input
            v-model="localPart"
            aria-label="Custom name"
            required
            autocomplete="off"
            spellcheck="false"
        /></label>
        <label class="flex flex-col gap-2"
          >Domain<select v-model="domain" aria-label="Domain">
            <option
              v-for="choice in account.domains"
              :key="choice"
              :value="choice"
            >
              {{ choice }}
            </option>
          </select></label
        >
      </template>
      <label
        class="flex flex-col gap-2"
        :class="{
          'summary-label': error && error.kind !== 'limit' && !editing,
        }"
        ><span v-if="!error || error.kind === 'limit' || editing"
          >Description</span
        ><input
          v-model="description"
          aria-label="Description"
          placeholder="Description (optional)"
      /></label>
      <button
        v-if="error && error.kind !== 'limit' && !editing"
        type="button"
        class="text-left"
        @click="editing = true"
      >
        {{ custom ? localPart : "Random address" }} · {{ domain }}
      </button>
      <button
        v-if="error?.creationUncertain"
        type="button"
        class="primary"
        @click="$emit('check')"
      >
        Refresh aliases
      </button>
      <button
        v-else
        class="primary"
        type="submit"
        :disabled="busy || !account.capabilities.can_create"
      >
        {{
          busy
            ? "Creating…"
            : error && error.kind !== "limit"
              ? "Try again"
              : "Create & copy alias"
        }}
      </button>
    </form>
  </section>
</template>
