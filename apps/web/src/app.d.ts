import type { Fetcher, Hyperdrive } from "@cloudflare/workers-types";

declare global {
  namespace App {
    interface Platform {
      env: {
        HYPERDRIVE: Hyperdrive;
        JOBS: Fetcher;
        DOCS_URL?: string;
        ENVIRONMENT?: string;
      };
    }
  }
}
export {};
