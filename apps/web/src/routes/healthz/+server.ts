/**
 * Liveness for uptime monitors: a fixed 200 "ok" with no database, upstream calls, secrets or
 * auth. Behind Cloudflare Access it needs a bypass path (infra/cloud machine_paths), or the
 * Access login page answers 200 and hides an outage.
 */
export function GET() {
  return new Response("ok", {
    headers: { "content-type": "text/plain", "cache-control": "no-store" },
  });
}
