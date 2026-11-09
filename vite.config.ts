import { configDefaults, defineConfig } from "vite-plus";

export default defineConfig({
  test: {
    exclude: [
      ...configDefaults.exclude,
      ".claude/**",
      "**/*.integration.test.ts",
      "**/*.e2e.test.ts",
      "**/.bun-cache/**",
    ],
  },
  fmt: {
    // drizzle-kit snapshots keep the layout the generator writes.
    ignorePatterns: ["packages/db/migrations-postgres/meta/**"],
    overrides: [
      {
        // Keep Wrangler configs readable by tools that parse strict JSON after stripping comments.
        files: ["apps/*/wrangler.jsonc"],
        options: { trailingComma: "none" },
      },
    ],
  },
  lint: {
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
    overrides: [
      {
        // Tests import from vitest and @playwright/test directly.
        files: ["**/*.test.ts", "tests/**/*.ts"],
        rules: { "vite-plus/prefer-vite-plus-imports": "off" },
      },
    ],
  },
  run: {
    cache: true,
  },
});
