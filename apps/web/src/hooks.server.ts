import { building } from "$app/environment";
import { handleErrorWithSentry, sentryHandle } from "@sentry/sveltekit";
import { sequence } from "@sveltejs/kit/hooks";
import type { Handle } from "@sveltejs/kit";
import { AccessError, verifyAccess } from "$lib/server/access";
import { PUBLIC_PATHS, secureHeaders } from "$lib/server/security";
import { initSentry } from "$lib/server/sentry";

// SvelteKit's own CSRF check (form posts must come from this origin) stays on: no trustedOrigins.
export const appHandle: Handle = async ({ event, resolve }) => {
  if (building) return resolve(event);
  try {
    if (!PUBLIC_PATHS.has(event.url.pathname)) {
      try {
        // Only ENVIRONMENT=local skips this; a hosted env without Access config fails closed (503).
        event.locals.viewer = await verifyAccess(
          event.request.headers,
          event.platform?.env ?? { ENVIRONMENT: "local" },
        );
      } catch (error) {
        if (error instanceof AccessError)
          return secureHeaders(new Response(error.message, { status: error.status }));
        throw error;
      }
    }
    return secureHeaders(await resolve(event));
  } finally {
    if (event.locals.db) await event.locals.db.$client.end();
  }
};

export const handle: Handle = sequence(initSentry, sentryHandle(), appHandle);

export const handleError = handleErrorWithSentry(({ error }: { error: unknown }) => {
  // Logged server-side and sent to Sentry; visitors get a generic message.
  console.error(error);
  return { message: "This request could not be completed. Please try again." };
});
