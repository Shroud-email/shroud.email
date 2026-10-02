import tippy from "tippy.js";

export function createCopyToClipboardHook({
  createTooltip = tippy,
  writeText = (text) => navigator.clipboard.writeText(text),
} = {}) {
  return {
    mounted() {
      this.tooltip = createTooltip(this.el, {
        content: "Copy to clipboard",
        hideOnClick: false,
      });

      this.copy = async () => {
        clearTimeout(this.resetTimer);
        try {
          await writeText(this.el.dataset.clipboardText);
          this.tooltip.setContent("Copied!");
        } catch {
          this.tooltip.setContent("Copy failed — please copy manually");
        }
        this.resetTimer = setTimeout(
          () => this.tooltip.setContent("Copy to clipboard"),
          2000,
        );
      };

      this.el.addEventListener("click", this.copy);
    },

    destroyed() {
      clearTimeout(this.resetTimer);
      this.el.removeEventListener("click", this.copy);
      this.tooltip.destroy();
    },
  };
}

export const CopyToClipboard = createCopyToClipboardHook();

export const Modal = {
  mounted() {
    window.modalHook = this;
  },

  destroyed() {
    window.modalHook = null;
  },

  modalClosing() {
    // Inform modal component when leave transition completes.
    setTimeout(() => {
      const selector = "#" + this.el.id;
      if (document.querySelector(selector)) {
        this.pushEventTo(selector, "hide", {});
      }
    }, 300);
  },
};
