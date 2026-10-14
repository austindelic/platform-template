import { configDefaults, defineConfig } from "vite-plus";

export default defineConfig({
  test: {
    exclude: [...configDefaults.exclude, "**/*.integration.test.ts", "**/*.e2e.test.ts", "**/.bun-cache/**"],
  },
});
