module.exports = {
  purge: ["./js/**/*.js", "../lib/shroud_web/**/*.*ex"],
  theme: {
    extend: {},
  },
  variants: {
    extend: {},
  },
  plugins: [
    require("daisyui"),
  ],
}
