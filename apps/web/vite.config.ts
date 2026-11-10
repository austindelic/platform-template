import { sentrySvelteKit } from "@sentry/sveltekit/vite";
import adapter from "@sveltejs/adapter-cloudflare";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig, lazyPlugins } from "vite-plus";

export default defineConfig({
  // Let Wrangler bundle the database adapter and its Node-compatible pg dependencies.
  build: { rolldownOptions: { external: ["pg"] } },
  plugins: lazyPlugins(() => [
    // Must come before sveltekit(). Source maps upload only when scripts/release.sh provides
    // SENTRY_AUTH_TOKEN (with SENTRY_ORG and SENTRY_PROJECT); every other build skips it.
    sentrySvelteKit({
      adapter: "cloudflare",
      autoUploadSourceMaps: Boolean(process.env.SENTRY_AUTH_TOKEN),
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
      release: { name: process.env.SENTRY_RELEASE },
      telemetry: false,
    }),
    sveltekit({
      env: { dir: "../.." },
      adapter: adapter({
        platformProxy: {
          configPath: process.env.WRANGLER_CONFIG ?? "wrangler.jsonc",
          persist: { path: process.env.WRANGLER_PERSIST_PATH ?? "../../.wrangler/state" },
        },
      }),
    }),
  ]),
});
