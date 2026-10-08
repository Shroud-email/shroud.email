import tippy from "tippy.js";

export function createCopyToClipboardHook({
  createTooltip = tippy,
  writeText = (text) => navigator.clipboard.writeText(text),
} = {}) {
  return {
    mounted() {
      this.copyRequest = 0;
      this.feedback = this.el.querySelector("[data-copy-feedback]");
      this.status = this.el.querySelector("[data-copy-status]");
      this.tooltip = createTooltip(this.el, {
        content: "Copy to clipboard",
        hideOnClick: false,
      });

      this.copy = async (event) => {
        this.feedback?.classList.toggle(
          "is-keyboard-copy",
          event?.detail === 0,
        );
        const request = ++this.copyRequest;
        clearTimeout(this.resetTimer);
        try {
          await writeText(this.el.dataset.clipboardText);
          if (request !== this.copyRequest) return;
          this.setFeedback(true, "Copied!");
        } catch {
          if (request !== this.copyRequest) return;
          this.setFeedback(false, "Copy failed — please copy manually");
          if (this.el.dataset.copyErrorEvent) {
            this.pushEvent(this.el.dataset.copyErrorEvent, {});
          }
        }
        this.resetTimer = setTimeout(
          () => this.setFeedback(false, "Copy to clipboard"),
          2000,
        );
      };

      this.el.addEventListener("click", this.copy);
    },

    setFeedback(copied, message) {
      this.feedback?.classList.toggle("is-copied", copied);
      if (this.status) {
        this.status.textContent =
          message === "Copy to clipboard" ? "" : message;
      }
      this.tooltip.setContent(message);
    },

    destroyed() {
      this.copyRequest++;
      clearTimeout(this.resetTimer);
      this.el.removeEventListener("click", this.copy);
      this.tooltip.destroy();
    },
  };
}

export const CopyToClipboard = createCopyToClipboardHook();

export const AliasDetailsForm = {
  mounted() {
    this.editing = false;
    this.instant = true;
    this.onPointerDown = () => {
      this.instant = false;
      this.el.dataset.instant = "false";
    };
    this.onKeyDown = (event) => {
      this.instant = true;
      this.el.dataset.instant = "true";
      if (
        event.target.matches("textarea") &&
        event.key === "Enter" &&
        (event.metaKey || event.ctrlKey) &&
        !event.isComposing
      ) {
        event.preventDefault();
        const submit = this.el.querySelector('button[type="submit"]');
        if (!event.repeat && !submit.disabled) this.el.requestSubmit(submit);
      }
    };
    this.el.addEventListener("pointerdown", this.onPointerDown, true);
    this.el.addEventListener("keydown", this.onKeyDown, true);
    this.updated();
  },

  updated() {
    this.el.dataset.instant = String(this.instant);
    if (this.instant) {
      this.el
        .querySelector(".alias-details-content")
        .getAnimations()
        .forEach((animation) => animation.cancel());
    }
    const editor = this.el.querySelector('input[type="text"], textarea');
    if (editor && !this.editing) {
      editor.focus();
      editor.setSelectionRange(editor.value.length, editor.value.length);
    }
    if (
      !editor &&
      this.editing &&
      (document.activeElement === document.body ||
        this.el.contains(document.activeElement))
    ) {
      this.el.querySelector('[id^="edit-alias-"]').focus();
    }
    this.editing = Boolean(editor);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown, true);
    this.el.removeEventListener("keydown", this.onKeyDown, true);
  },
};

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
