const { defineConfig } = require("@playwright/test")

module.exports = defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL: process.env.BASE_URL || "http://localhost:4400",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure"
  },
  reporter: process.env.CI ? [["line"], ["html", { open: "never" }]] : "list",
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
  webServer: undefined
})
