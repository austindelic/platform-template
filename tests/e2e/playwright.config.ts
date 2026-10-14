import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  testMatch: "*.e2e.ts",
  use: { baseURL: "http://127.0.0.1:5177" },
  webServer: {
    command: "mise exec -- bun run --cwd apps/web dev --host 127.0.0.1",
    url: "http://127.0.0.1:5177",
    reuseExistingServer: !process.env.CI,
  },
});
