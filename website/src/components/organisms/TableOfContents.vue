<script setup lang="ts">
import type { PropType } from "vue";
import useTableOfContents from "~/composables/useTableOfContents";
import type { Heading } from "~/types";

const props = defineProps({
  tableOfContents: {
    type: Object as PropType<Heading[]>,
    required: true,
  },
});

const currentSection = useTableOfContents(props.tableOfContents);
function isActive(section: Heading) {
  return section.slug === currentSection.value;
}
</script>

<template>
  <div
    class="hidden xl:sticky xl:top-18 xl:-mr-6 xl:block xl:h-[calc(100vh-4.5rem-8rem)] xl:flex-none xl:overflow-y-auto xl:py-16 xl:pr-6">
    <nav aria-labelledby="on-this-page-title" class="w-56">
      <template v-if="tableOfContents.length > 0">
        <h2 id="on-this-page-title" class="font-display text-sm font-medium text-slate-900 dark:text-white">
          On this page
        </h2>
        <ul class="mt-4 space-y-3 text-sm">
          <li v-for="section in tableOfContents" :key="section.slug">
            <h3>
              <a :href="`#${section.slug}`"
                :class="isActive(section) ? 'text-sky-500' : 'font-normal text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-300'">
                {{ section.text }}
              </a>
            </h3>
          </li>
        </ul>
      </template>
    </nav>
  </div>
</template>
