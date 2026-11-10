import { initCloudflareSentryHandle } from "@sentry/sveltekit";
import type { Handle } from "@sveltejs/kit";

/**
 * Starts Sentry on the first request, because the DSN is a Worker secret that exists only on
 * `event.platform.env`. Without `SENTRY_DSN` (local development, tests) the SDK stays off.
 * Sentry's defaults apply: personal data (cookies, IP addresses, request bodies) is not sent.
 */
let started: Handle | undefined;
export const initSentry: Handle = (input) => {
  const env = input.event.platform?.env;
  const dsn = typeof env?.SENTRY_DSN === "string" ? env.SENTRY_DSN : undefined;
  started ??= initCloudflareSentryHandle({ dsn, environment: env?.ENVIRONMENT ?? "unknown" });
  return started(input);
};
