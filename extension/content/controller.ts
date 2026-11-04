import { createApp, type App } from "vue";
import InlineMenu from "./InlineMenu.vue";
import { discoverFields, observeFields } from "./fields";
import logo from "../assets/logo.svg?raw";

export function startFields(document: Document, css: string, fontUrl: string) {
  const view = document.defaultView!;
  const font = new view.FontFace(
    "Shroud Inter",
    `url(${JSON.stringify(fontUrl)})`,
    { weight: "100 900" },
  );
  document.fonts.add(font);
  void font.load().catch(() => {});
  const host = document.createElement("div");
  host.dataset.shroudOwned = "";
  host.style.cssText =
    "all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none";
  const root = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  style.textContent =
    css +
    '.shroud-ui { font-family: "Shroud Inter", Inter, system-ui, sans-serif; }';
  root.append(style);
  document.documentElement.append(host);
  for (const type of ["click", "keydown", "input", "change"]) {
    root.addEventListener(
      type,
      (event) => {
        if (!event.isTrusted) event.stopImmediatePropagation();
      },
      true,
    );
  }
  const icons = new Map<HTMLInputElement, HTMLButtonElement>();
  let app: App | null = null;
  let menu: HTMLDivElement | null = null;
  let target: HTMLInputElement | null = null;
  let busy = false;
  let stopped = false;
  const resize = new ResizeObserver(() => scan());
  function close() {
    app?.unmount();
    app = null;
    menu?.remove();
    menu = null;
    busy = false;
    if (target?.isConnected) target.focus({ preventScroll: true });
    target = null;
  }
  function open(input: HTMLInputElement) {
    if (busy) return;
    close();
    target = input;
    menu = document.createElement("div");
    menu.className = "inline-container";
    root.append(menu);
    app = createApp(InlineMenu, {
      target: input,
      onClose: close,
      onBusy: (value: boolean) => {
        busy = value;
      },
    });
    app.mount(menu);
    positionMenu();
    menu.querySelector<HTMLElement>("button")?.focus();
  }
  function setPosition(element: HTMLElement, left: number, top: number) {
    if (element.style.left !== `${left}px`) element.style.left = `${left}px`;
    if (element.style.top !== `${top}px`) element.style.top = `${top}px`;
  }
  function positionMenu() {
    if (!menu || !target?.isConnected) return;
    const rect = target.getBoundingClientRect();
    const width = Math.min(348, view.innerWidth - 16);
    const below = view.innerHeight - rect.bottom - 16;
    const above = rect.top - 16;
    const flip = below < 180 && above > below;
    menu.style.width = `${width}px`;
    menu.style.maxHeight = `${Math.max(44, flip ? above : below)}px`;
    menu.style.transform = flip ? "translateY(-100%)" : "";
    setPosition(
      menu,
      Math.max(
        8,
        Math.min(rect.right - width + 26, view.innerWidth - width - 8),
      ),
      flip ? rect.top - 8 : rect.bottom + 8,
    );
  }
  function position(input: HTMLInputElement, icon: HTMLButtonElement) {
    const rect = input.getBoundingClientRect();
    let left = rect.right - 36;
    const top = rect.top + (rect.height - 28) / 2;
    for (let attempt = 0; attempt < 3; attempt++) {
      const hit = document
        .elementsFromPoint(left + 14, top + 14)
        .find((e) => e !== host);
      if (!hit || hit === input || hit.contains(input)) break;
      left -= 32;
    }
    icon.hidden =
      rect.bottom < 0 || rect.top > view.innerHeight || left < rect.left + 4;
    setPosition(icon, left, top);
  }
  function scan(fields = discoverFields(document)) {
    if (stopped) return;
    for (const [input, icon] of icons) {
      if (!fields.includes(input)) {
        icon.remove();
        icons.delete(input);
        resize.unobserve(input);
      }
    }
    for (const input of fields) {
      if (!icons.has(input)) {
        const icon = document.createElement("button");
        icon.type = "button";
        icon.className = "field-icon";
        icon.setAttribute("aria-label", "Use a Shroud.email alias");
        icon.innerHTML = logo;
        icon.addEventListener("click", () => open(input));
        root.append(icon);
        icons.set(input, icon);
        resize.observe(input);
      }
      position(input, icons.get(input)!);
    }
    positionMenu();
  }
  const unobserve = observeFields(document, scan);
  const outside = (event: PointerEvent) => {
    if (menu && !event.composedPath().includes(host)) close();
  };
  const escape = (event: KeyboardEvent) => {
    if (event.isTrusted && event.key === "Escape" && menu) {
      event.preventDefault();
      close();
    }
  };
  const reposition = () => scan();
  document.addEventListener("pointerdown", outside, true);
  document.addEventListener("keydown", escape, true);
  view.addEventListener("scroll", reposition, true);
  view.addEventListener("resize", reposition);
  return {
    refresh: reposition,
    stop() {
      stopped = true;
      document.fonts.delete(font);
      unobserve();
      resize.disconnect();
      close();
      host.remove();
      icons.clear();
      document.removeEventListener("pointerdown", outside, true);
      document.removeEventListener("keydown", escape, true);
      view.removeEventListener("scroll", reposition, true);
      view.removeEventListener("resize", reposition);
    },
  };
}
