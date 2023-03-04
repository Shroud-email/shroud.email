export const Notification = {
  mounted() {
    const hide = () =>
      liveSocket.execJS(this.el, this.el.getAttribute("phx-click"));
    this.timer = setTimeout(() => hide(), 8000);
    this.el.addEventListener("phx:hide-start", () => clearTimeout(this.timer));
    this.el.addEventListener("mouseover", () => {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => hide(), 8000);
    });
  },

  destroyed() {
    clearTimeout(this.timer);
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
