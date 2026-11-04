<script setup lang="ts">
import { request, type Capabilities } from "../shared/contracts";
defineProps<{ capabilities: Capabilities }>();
const emit = defineEmits<{ error: [message: string] }>();
async function upgrade() {
  try {
    const result = await request({ type: "open", destination: "billing" });
    if (!result.ok) emit("error", result.error.message);
  } catch {
    emit("error", "Could not open billing. Try again.");
  }
}
</script>
<template>
  <aside
    v-if="
      capabilities.alias_limit !== null &&
      capabilities.alias_count >= capabilities.alias_limit
    "
    class="limit flex flex-col gap-2"
    role="status"
  >
    <strong>Alias limit reached</strong>
    <p>
      Free plan: {{ capabilities.alias_count }}/{{
        capabilities.alias_limit
      }}
      aliases used.
    </p>
    <button class="link text-left" @click="upgrade">Upgrade ↗</button>
  </aside>
</template>
