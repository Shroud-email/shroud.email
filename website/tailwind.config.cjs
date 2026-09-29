const defaultTheme = require("tailwindcss/defaultTheme")

module.exports = {
  content: [
    "./public/**/*.html",
    "./src/**/*.{astro,js,jsx,svelte,ts,tsx,vue,md}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Manrope", ...defaultTheme.fontFamily.sans],
        display: ["Newsreader", ...defaultTheme.fontFamily.serif],
      },
      maxWidth: {
        '8xl': '88rem',
      },
    },
  },
  plugins: [require("@tailwindcss/forms"), require("@tailwindcss/typography")]
};
