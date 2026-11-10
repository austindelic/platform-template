/** Paths that answer without an Access identity. Keep in step with machine_paths in infra/cloud. */
export const PUBLIC_PATHS = new Set(["/healthz"]);

/**
 * Response headers every page gets. Responses are never stored unless a route marks them
 * `private, immutable`; referrer and MIME sniffing are locked down.
 */
export function secureHeaders(response: Response) {
  if (!/^private,.*\bimmutable\b/.test(response.headers.get("cache-control") ?? ""))
    response.headers.set("cache-control", "private, no-store");
  if (!response.headers.has("referrer-policy"))
    response.headers.set("referrer-policy", "same-origin");
  response.headers.set("x-content-type-options", "nosniff");
  return response;
}
