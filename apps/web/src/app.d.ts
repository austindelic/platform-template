import type { ExecutionContext, Fetcher, Hyperdrive } from "@cloudflare/workers-types";
import type { Db } from "@starter/db";
import type { Viewer } from "$lib/server/access";

declare global {
  namespace App {
    interface Locals {
      /** Created on first use by $lib/server/db and closed by hooks.server.ts. */
      db?: Db;
      /** Who Cloudflare Access let in (hooks.server.ts). Unset on PUBLIC_PATHS. */
      viewer?: Viewer;
    }
    interface Platform {
      env: {
        HYPERDRIVE: Hyperdrive;
        JOBS: Fetcher;
        DOCS_URL?: string;
        ENVIRONMENT?: string;
        CF_ACCESS_TEAM_DOMAIN?: string;
        CF_ACCESS_AUD?: string;
        SENTRY_DSN?: string;
      };
      context: ExecutionContext;
    }
  }
}
export {};
