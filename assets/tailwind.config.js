const defaultTheme = require("tailwindcss/defaultTheme");

module.exports = {
  content: ["./js/**/*.js", "../lib/shroud_web/**/*.*ex"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter var", ...defaultTheme.fontFamily.sans],
      },
    },
  },
  variants: {
    extend: {},
  },
  plugins: [require("@tailwindcss/forms"), require("@tailwindcss/typography")],
};
