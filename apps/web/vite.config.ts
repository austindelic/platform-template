import adapter from "@sveltejs/adapter-cloudflare";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig, lazyPlugins } from "vite-plus";

export default defineConfig({
  build: { rolldownOptions: { external: ["pg"] } },
  plugins: lazyPlugins(() => [
    sveltekit({
      env: { dir: "../.." },
      adapter: adapter({
        platformProxy: { configPath: "wrangler.jsonc", persist: { path: "../../.wrangler/state" } },
      }),
    }),
  ]),
});
