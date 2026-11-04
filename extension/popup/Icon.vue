<script setup lang="ts">
defineProps<{ name: "settings" | "copy" }>();
</script>
<template>
  <svg
    v-if="name === 'copy'"
    width="18"
    height="18"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.7"
    aria-hidden="true"
  >
    <rect x="8" y="8" width="12" height="13" rx="2" />
    <path d="M16 8V3H3v13h5" />
  </svg>
  <svg
    v-else
    width="20"
    height="20"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.7"
    aria-hidden="true"
  >
    <path d="M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1z" />
    <circle cx="12" cy="12" r="3" />
  </svg>
</template>
