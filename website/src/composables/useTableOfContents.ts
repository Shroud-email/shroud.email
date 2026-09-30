import { onMounted, onUnmounted, ref } from "vue";
import type { Heading } from "~/types";

export default (headings: Heading[]) => {
  const currentSection = ref(headings[0]?.slug);

  function onScroll() {
    if (headings.length === 0) return;

    const sortedHeadings = headings
      .map(({ slug, text, depth }) => {
        const el = document.getElementById(slug);
        if (!el) return null;

        const style = window.getComputedStyle(el);
        const scrollMt = parseFloat(style.scrollMarginTop);
        const top = window.scrollY + el.getBoundingClientRect().top - scrollMt;
        return { slug, text, top, depth };
      })
      .filter((h) => !!h)
      .sort((a, b) => (a?.top || 0) - (b?.top || 0));

    const top = window.scrollY;
    let current = sortedHeadings[0]?.slug;
    sortedHeadings.forEach((sortedHeading) => {
      if (top >= (sortedHeading?.top || 0)) {
        current = sortedHeading?.slug;
      }
    });
    currentSection.value = current;
  }

  onMounted(() => {
    window.addEventListener("scroll", onScroll, {
      capture: true,
    });
    onScroll();
  });

  onUnmounted(() => {
    window.removeEventListener("scroll", onScroll, {
      capture: true,
    });
  });

  return currentSection;
};
