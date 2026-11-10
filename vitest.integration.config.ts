import { configDefaults, defineConfig } from "vite-plus";
import config from "./vite.config.ts";

// Integration tests run only against an explicitly disposable database: never DATABASE_URL.
if (!process.env.TEST_DATABASE_URL?.trim()) {
  throw new Error("TEST_DATABASE_URL is required and must point to a disposable test database.");
}

export default defineConfig({
  test: {
    ...config.test,
    include: ["tests/integration/**/*.integration.test.ts", "apps/*/src/**/*.integration.test.ts"],
    exclude: [...configDefaults.exclude],
  },
});
