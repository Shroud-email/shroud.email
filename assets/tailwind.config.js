module.exports = {
  purge: ["./js/**/*.js", "../lib/shroud_web/**/*.*ex"],
  mode: "jit",
  theme: {
    extend: {},
  },
  variants: {
    extend: {},
  },
  plugins: [
    require("daisyui"),
  ],
  options: {
    safelist: [
      /data-theme$/,
    ]
  },
  daisyui: {
    themes: ["dark"],
  },
}
