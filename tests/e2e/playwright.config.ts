import { defineConfig, devices } from "@playwright/test";
import { fileURLToPath } from "node:url";

// Playwright runs webServer commands from this config's directory, so point it at the repo root.
const root = fileURLToPath(new URL("../..", import.meta.url));

export default defineConfig({
  testDir: ".",
  testMatch: "*.e2e.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI
    ? [["github"], ["list"], ["html", { open: "never", outputFolder: "../../playwright-report" }]]
    : "list",
  use: { baseURL: "http://127.0.0.1:5177", trace: "retain-on-failure" },
  projects: [
    {
      name: "desktop",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } },
    },
    { name: "phone", use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: "bun run --cwd apps/web dev",
    cwd: root,
    url: "http://127.0.0.1:5177",
    reuseExistingServer: !process.env.CI,
  },
});
