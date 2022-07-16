export const Modal = {
  mounted() {
    window.modalHook = this
  },

  destroyed() {
    window.modalHook = null
  },

  modalClosing() {
    // Inform modal component when leave transition completes.
    setTimeout(() => {
      const selector = '#' + this.el.id
      if (document.querySelector(selector)) {
        this.pushEventTo(selector, "hide", {})
      }
    }, 300);
  }
}
