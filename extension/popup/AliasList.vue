<script setup lang="ts">
import type { AccountView, AliasPage } from "../shared/contracts";
import Icon from "./Icon.vue";
import LimitNotice from "./LimitNotice.vue";
defineProps<{
  account: AccountView;
  page: AliasPage | null;
  searching: boolean;
}>();
const query = defineModel<string>({ required: true });
defineEmits<{
  create: [];
  settings: [];
  copy: [address: string];
  page: [page: number];
  error: [message: string];
}>();
</script>
<template>
  <section
    class="screen aliases flex flex-col gap-3"
    :class="{ 'at-limit': !account.capabilities.can_create }"
  >
    <header class="flex h-8 items-center justify-between">
      <h1>Aliases</h1>
      <button
        class="icon-button"
        aria-label="Settings"
        @click="$emit('settings')"
      >
        <Icon name="settings" />
      </button>
    </header>
    <LimitNotice
      :capabilities="account.capabilities"
      @error="$emit('error', $event)"
    />
    <button
      class="primary"
      :disabled="!account.capabilities.can_create"
      @click="$emit('create')"
    >
      + New alias
    </button>
    <input
      v-model="query"
      type="search"
      aria-label="Search aliases"
      placeholder="Search address or description"
      class="search"
    />
    <div class="flex justify-between">
      <strong>{{ query ? "Search results" : "All aliases" }}</strong
      ><span class="muted">{{
        page?.total_entries ?? account.capabilities.alias_count
      }}</span>
    </div>
    <div class="alias-rows" :aria-busy="searching">
      <p v-if="searching" class="p-4 muted" role="status">Loading aliases…</p>
      <p v-else-if="!page?.email_aliases.length" class="p-4 muted">
        {{ query ? "No matching aliases." : "No aliases yet." }}
      </p>
      <div
        v-for="alias in page?.email_aliases"
        :key="alias.address"
        :data-address="alias.address"
        class="alias-row flex items-center justify-between gap-2"
      >
        <div class="flex min-w-0 flex-col gap-1">
          <p class="font-medium break-all">{{ alias.address }}</p>
          <div class="flex flex-wrap items-center gap-2">
            <span v-if="alias.title" class="muted break-words">{{
              alias.title
            }}</span
            ><span
              class="status"
              :class="alias.enabled ? 'enabled' : 'disabled'"
              >{{ alias.enabled ? "Enabled" : "Disabled" }}</span
            >
          </div>
        </div>
        <button
          class="icon-button shrink-0"
          :aria-label="`Copy ${alias.address}`"
          @click="$emit('copy', alias.address)"
        >
          <Icon name="copy" />
        </button>
      </div>
    </div>
    <nav
      v-if="page && page.total_pages > 1"
      class="flex items-center justify-between gap-2"
      aria-label="Alias pages"
    >
      <button
        class="link"
        :disabled="searching || page.page_number <= 1"
        @click="$emit('page', page.page_number - 1)"
      >
        Previous</button
      ><span class="muted">{{ page.page_number }} / {{ page.total_pages }}</span
      ><button
        class="link"
        :disabled="searching || page.page_number >= page.total_pages"
        @click="$emit('page', page.page_number + 1)"
      >
        Next
      </button>
    </nav>
  </section>
</template>
