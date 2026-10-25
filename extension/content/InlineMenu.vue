<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from "vue";
import {
  request,
  type AccountView,
  type Alias,
  type AliasPage,
} from "../shared/contracts";
import LimitNotice from "../popup/LimitNotice.vue";
import { fillField } from "./fields";
const props = defineProps<{ target: HTMLInputElement }>();
const emit = defineEmits<{ close: []; busy: [value: boolean] }>();
const account = ref<AccountView | null>(null);
const domain = ref("");
const domainOpen = ref(false);
const choosingDomain = ref(false);
const browse = ref(false);
const query = ref("");
const page = ref<AliasPage | null>(null);
const loading = ref(true);
const busy = ref(false);
const created = ref<Alias | null>(null);
const message = ref("");
const uncertain = ref(false);
let active = true;
let searchVersion = 0;
onUnmounted(() => {
  active = false;
  searchVersion++;
});
async function loadAliases(number = 1) {
  const version = ++searchVersion;
  loading.value = true;
  try {
    const result = await request({
      type: "aliases",
      search: query.value,
      page: number,
      recent: !browse.value,
    });
    if (!active || version !== searchVersion) return;
    if (!result.ok) {
      message.value = result.error.message;
      return;
    }
    page.value = result.value;
    uncertain.value = false;
  } catch {
    if (active && version === searchVersion)
      message.value = "Could not load aliases. Try again.";
  } finally {
    if (active && version === searchVersion) loading.value = false;
  }
}
onMounted(async () => {
  try {
    const result = await request({ type: "account" });
    if (!active) return;
    if (!result.ok) {
      message.value = result.error.message;
      loading.value = false;
      return;
    }
    account.value = result.value;
    if (!result.value) {
      message.value = "Sign in using the Shroud.email toolbar button.";
      loading.value = false;
      return;
    }
    domain.value = result.value.preferences.selectedDomain;
    await loadAliases();
  } catch {
    if (active) {
      message.value = "Could not load your account. Try again.";
      loading.value = false;
    }
  }
});
watch(query, () => {
  void loadAliases();
});
async function chooseDomain(value: string) {
  domainOpen.value = false;
  if (busy.value || choosingDomain.value) return;
  choosingDomain.value = true;
  try {
    const result = await request({ type: "selected-domain", domain: value });
    if (!active) return;
    if (result.ok) domain.value = value;
    else message.value = result.error.message;
  } catch {
    if (active) message.value = "Could not select this domain. Try again.";
  } finally {
    choosingDomain.value = false;
  }
}
function fill(alias: Alias) {
  if (!alias.enabled || busy.value) return;
  if (fillField(props.target, alias.address)) emit("close");
  else {
    created.value = alias;
    message.value =
      "The email field is no longer available. Copy this alias instead.";
  }
}
async function create() {
  if (
    busy.value ||
    choosingDomain.value ||
    created.value ||
    uncertain.value ||
    !account.value?.capabilities.can_create
  )
    return;
  busy.value = true;
  emit("busy", true);
  message.value = "";
  try {
    const result = await request({
      type: "create",
      input: { domain: domain.value },
    });
    if (!active) return;
    if (!result.ok) {
      message.value = result.error.message;
      uncertain.value = !!result.error.creationUncertain;
      if (result.error.kind === "limit") {
        const fresh = await request({ type: "account" });
        if (active && fresh.ok) account.value = fresh.value;
      }
      return;
    }
    created.value = result.value;
    if (fillField(props.target, result.value.address)) emit("close");
    else
      message.value =
        "The email field is no longer available. Copy this alias instead.";
  } catch {
    if (active) {
      message.value =
        "Creation could not be confirmed. Refresh aliases before trying again.";
      uncertain.value = true;
    }
  } finally {
    busy.value = false;
    emit("busy", false);
  }
}
async function copy() {
  if (!created.value) return;
  try {
    await navigator.clipboard.writeText(created.value.address);
    if (active) message.value = "Copied to clipboard.";
  } catch {
    if (active)
      message.value =
        "Could not copy. Select the address and copy it manually, or try Copy again.";
  }
}
async function showBrowse() {
  browse.value = true;
  domainOpen.value = false;
  await loadAliases();
}
</script>
<template>
  <section
    class="shroud-ui inline-menu flex flex-col gap-3.5"
    :data-appearance="account?.preferences.appearance ?? 'system'"
    aria-label="Use a Shroud.email alias"
  >
    <header class="flex items-center justify-between gap-2">
      <strong>{{ browse ? "Aliases" : "Use a Shroud.email alias" }}</strong
      ><button
        v-if="browse"
        class="link"
        @click="
          browse = false;
          query = '';
          loadAliases();
        "
      >
        Back
      </button>
    </header>
    <p v-if="message" role="status" class="muted">{{ message }}</p>
    <template v-if="created"
      ><p class="font-medium break-all select-text">{{ created.address }}</p>
      <button class="primary" @click="copy">Copy</button></template
    >
    <template v-else-if="account">
      <LimitNotice
        :capabilities="account.capabilities"
        @error="message = $event"
      />
      <template v-if="!browse">
        <div
          v-if="account.domains.length > 1"
          class="relative flex flex-col gap-2"
        >
          <span class="muted">Domain</span>
          <button
            class="domain-button flex items-center justify-between gap-2"
            aria-label="Domain"
            :aria-expanded="domainOpen"
            :disabled="busy || choosingDomain"
            @click="domainOpen = !domainOpen"
          >
            <span class="truncate">{{ domain }}</span
            ><span>⌄</span>
          </button>
          <div
            v-if="domainOpen"
            class="domain-options flex flex-col"
            role="listbox"
            aria-label="Alias domain"
          >
            <button
              v-for="option in account.domains"
              :key="option"
              role="option"
              :data-domain="option"
              :aria-selected="option === domain"
              class="flex items-center justify-between gap-2"
              @click="chooseDomain(option)"
            >
              <span class="truncate">{{ option }}</span
              ><span
                v-if="option === account.capabilities.default_domain"
                class="muted text-xs"
                >Default</span
              ><span v-if="option === domain">✓</span>
            </button>
          </div>
        </div>
        <button
          class="primary"
          :disabled="
            busy ||
            choosingDomain ||
            uncertain ||
            !account.capabilities.can_create
          "
          @click="create"
        >
          {{ busy ? "Creating…" : "+ Create & fill" }}
        </button>
        <span class="muted">Recent aliases</span>
      </template>
      <template v-else
        ><input
          v-model="query"
          type="search"
          class="search"
          aria-label="Search aliases"
          placeholder="Search address or description"
        />
        <div class="flex justify-between">
          <strong>{{ query ? "Search results" : "All aliases" }}</strong
          ><span class="muted">{{ page?.total_entries }}</span>
        </div></template
      >
      <button v-if="uncertain" class="link text-left" @click="showBrowse">
        Refresh aliases
      </button>
      <p v-if="loading" class="muted" role="status">Loading aliases…</p>
      <div v-else class="inline-rows flex flex-col gap-3.5">
        <p v-if="!page?.email_aliases.length" class="muted">
          {{ query ? "No matching aliases." : "No aliases yet." }}
        </p>
        <div
          v-for="alias in browse
            ? page?.email_aliases
            : page?.email_aliases.filter((a) => a.enabled).slice(0, 3)"
          :key="alias.address"
          class="inline-row flex flex-col gap-1.5"
          :data-address="alias.address"
        >
          <p class="font-medium break-all">{{ alias.address }}</p>
          <div class="flex items-center justify-between gap-2">
            <span class="muted truncate">{{
              alias.title || (alias.enabled ? "" : "Disabled")
            }}</span
            ><button
              class="link shrink-0"
              :disabled="!alias.enabled || busy"
              @click="fill(alias)"
            >
              Fill email →
            </button>
          </div>
        </div>
      </div>
      <nav
        v-if="browse && page && page.total_pages > 1"
        class="flex justify-between gap-2"
        aria-label="Alias pages"
      >
        <button
          class="link"
          :disabled="loading || page.page_number <= 1"
          @click="loadAliases(page.page_number - 1)"
        >
          Previous</button
        ><span class="muted"
          >{{ page.page_number }} / {{ page.total_pages }}</span
        ><button
          class="link"
          :disabled="loading || page.page_number >= page.total_pages"
          @click="loadAliases(page.page_number + 1)"
        >
          Next
        </button>
      </nav>
      <footer v-if="!browse">
        <button class="link" :disabled="busy" @click="showBrowse">
          Browse all aliases ↗
        </button>
      </footer>
    </template>
  </section>
</template>
