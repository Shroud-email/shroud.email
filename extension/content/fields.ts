function editable(input: HTMLInputElement): boolean {
  if (
    !input.isConnected ||
    input.type !== "email" ||
    input.disabled ||
    input.readOnly ||
    input.closest("[hidden],[inert]")
  )
    return false;
  const view = input.ownerDocument.defaultView;
  if (!view) return false;
  for (
    let element: Element | null = input;
    element;
    element = element.parentElement
  ) {
    const style = view.getComputedStyle(element);
    if (
      style.display === "none" ||
      style.visibility === "hidden" ||
      style.visibility === "collapse"
    )
      return false;
  }
  const rect = input.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}
export function discoverFields(root: Document): HTMLInputElement[] {
  return [...root.querySelectorAll("input")].filter(editable);
}
export function fillField(input: HTMLInputElement, address: string): boolean {
  if (!editable(input)) return false;
  const view = input.ownerDocument.defaultView!;
  const setter = Object.getOwnPropertyDescriptor(
    view.HTMLInputElement.prototype,
    "value",
  )!.set!;
  setter.call(input, address);
  input.dispatchEvent(
    new view.Event("input", { bubbles: true, composed: true }),
  );
  input.dispatchEvent(
    new view.Event("change", { bubbles: true, composed: true }),
  );
  return true;
}
export function observeFields(
  root: Document,
  changed: (fields: HTMLInputElement[]) => void,
): () => void {
  const observer = new MutationObserver(() => changed(discoverFields(root)));
  observer.observe(root.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      "type",
      "disabled",
      "readonly",
      "hidden",
      "inert",
      "style",
      "class",
    ],
  });
  changed(discoverFields(root));
  return () => observer.disconnect();
}
