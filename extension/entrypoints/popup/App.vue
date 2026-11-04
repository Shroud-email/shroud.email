<script setup lang="ts">
import { computed, ref } from "vue";
import Login from "../../popup/Login.vue";
import AliasList from "../../popup/AliasList.vue";
import CreateAlias from "../../popup/CreateAlias.vue";
import Settings from "../../popup/Settings.vue";
import { useAccount } from "../../popup/useAccount";
import type { Appearance } from "../../shared/contracts";
const {
  account,
  screen,
  loaded,
  page,
  query,
  searching,
  error,
  creationError,
  creating,
  created,
  notice,
  refreshAccount,
  loadAliases,
  create,
  copy,
  checkUncertain,
  logout,
} = useAccount();
const signedOutAppearance = ref<Appearance>("system");
const appearance = computed(
  () => account.value?.preferences.appearance ?? signedOutAppearance.value,
);
function displayError(message: string) {
  error.value = { kind: "unknown", message };
}
</script>
<template>
  <main
    aria-label="Shroud.email"
    class="shroud-ui"
    :data-appearance="appearance"
  >
    <section v-if="!loaded" class="screen" role="status">Loading…</section>
    <Settings
      v-else-if="screen === 'settings'"
      :account="account"
      :appearance="appearance"
      @back="screen = 'aliases'"
      @refresh="refreshAccount"
      @logout="logout"
      @appearance="signedOutAppearance = $event"
    />
    <Login v-else-if="!account" @settings="screen = 'settings'" />
    <CreateAlias
      v-else-if="screen === 'create'"
      :account="account"
      :busy="creating"
      :created="created"
      :error="creationError"
      @back="screen = 'aliases'"
      @create="create"
      @copy="copy($event, true)"
      @check="checkUncertain"
      @error="displayError"
    />
    <AliasList
      v-else
      v-model="query"
      :account="account"
      :page="page"
      :searching="searching"
      @create="
        creationError = creationError?.creationUncertain ? creationError : null;
        created = null;
        screen = 'create';
      "
      @settings="screen = 'settings'"
      @copy="copy"
      @page="loadAliases"
      @error="displayError"
    />
    <p v-if="error" role="alert" class="popup-message failure">
      {{ error.message
      }}<button v-if="!account" class="link block" @click="refreshAccount">
        Check sign-in status
      </button>
    </p>
    <p v-if="notice" role="status" class="popup-message notice">{{ notice }}</p>
  </main>
</template>
