<script setup lang="ts">
import Accordion from "@nuxt/ui/components/Accordion.vue";
import "@nuxt/ui/runtime/keyframes.css";

defineProps<{
  questions: { question: string; answer: string }[];
}>();
</script>

<template>
  <Accordion
    type="multiple"
    :items="questions"
    label-key="question"
    :unmount-on-hide="false"
    class="mt-10 border-y border-slate-200 dark:border-slate-800"
    :ui="{
      item: 'border-slate-200 py-5 dark:border-slate-800',
      trigger: 'cursor-pointer items-start justify-between gap-4 rounded py-0 text-lg font-semibold text-slate-900 outline-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-4 dark:text-slate-100 dark:focus-visible:ring-offset-slate-950',
      body: 'pb-0 pt-4 text-base leading-relaxed text-slate-600 dark:text-slate-300',
    }"
  >
    <template #trailing="{ open }">
      <svg
        class="mt-1 size-5 flex-none text-indigo-500 transition-transform duration-200 ease-out motion-reduce:transition-none"
        :class="{ 'rotate-45': open }"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        aria-hidden="true"
      >
        <path d="M12 5v14m-7-7h14" />
      </svg>
    </template>
    <template #body="{ item }">
      <p>{{ item.answer }}</p>
    </template>
  </Accordion>
</template>
