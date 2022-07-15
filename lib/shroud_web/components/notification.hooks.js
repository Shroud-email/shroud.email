export const Hook = {
  mounted() {
    const hide = () => liveSocket.execJS(this.el, this.el.getAttribute("phx-click"))
    this.timer = setTimeout(() => hide(), 8000)
    this.el.addEventListener("phx:hide-start", () => clearTimeout(this.timer))
    this.el.addEventListener("mouseover", () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => hide(), 8000)
    })
  },

  destroyed(){
    clearTimeout(this.timer)
  },
}
