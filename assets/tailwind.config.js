module.exports = {
  content: ["./js/**/*.js", "../lib/shroud_web/**/*.*ex"],
  theme: {
    extend: {},
  },
  variants: {
    extend: {},
  },
  plugins: [require("daisyui")],
  options: {
    safelist: [/data-theme$/],
  },
  daisyui: {
    themes: ["dark"],
  },
}
