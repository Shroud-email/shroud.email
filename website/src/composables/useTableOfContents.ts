import { onMounted, onUnmounted, ref } from "vue";
import type { Heading } from "~/types";

export default (headings: Heading[]) => {
  const currentSection = ref(headings[0]?.slug);
  let sortedHeadings: Array<{ slug: string; top: number }> = [];
  let resizeObserver: ResizeObserver | undefined;
  let refreshFrame: number | undefined;

  function onScroll() {
    if (sortedHeadings.length === 0) return;

    const top = window.scrollY;
    let current = sortedHeadings[0]?.slug;
    sortedHeadings.forEach((sortedHeading) => {
      if (top >= sortedHeading.top) {
        current = sortedHeading.slug;
      }
    });
    currentSection.value = current;
  }

  function refreshHeadings() {
    sortedHeadings = headings
      .map(({ slug }) => {
        const el = document.getElementById(slug);
        if (!el) return null;

        const scrollMt = Number.parseFloat(
          window.getComputedStyle(el).scrollMarginTop,
        );
        const top =
          window.scrollY +
          el.getBoundingClientRect().top -
          (Number.isNaN(scrollMt) ? 0 : scrollMt);
        return { slug, top };
      })
      .filter((heading) => heading !== null)
      .sort((a, b) => a.top - b.top);
    onScroll();
  }

  function scheduleRefresh() {
    if (refreshFrame !== undefined) return;

    refreshFrame = window.requestAnimationFrame(() => {
      refreshFrame = undefined;
      refreshHeadings();
    });
  }

  onMounted(() => {
    window.addEventListener("scroll", onScroll, {
      capture: true,
      passive: true,
    });
    window.addEventListener("resize", scheduleRefresh);

    const article = document
      .getElementById(headings[0]?.slug ?? "")
      ?.closest("article");
    if (article) {
      resizeObserver = new ResizeObserver(scheduleRefresh);
      resizeObserver.observe(article);
    }

    refreshHeadings();
    scheduleRefresh();
  });

  onUnmounted(() => {
    window.removeEventListener("scroll", onScroll, true);
    window.removeEventListener("resize", scheduleRefresh);
    resizeObserver?.disconnect();
    if (refreshFrame !== undefined) {
      window.cancelAnimationFrame(refreshFrame);
    }
  });

  return currentSection;
};
