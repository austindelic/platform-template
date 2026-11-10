#!/usr/bin/env bash
# Runs one command against a hosted environment's database and storage (imports, seeding, a
# one-off query), with secrets passed only to that command:
#
#   RUNTIME_PROJECT_ID=... DEPLOY_PROJECT_ID=... scripts/hosted.sh staging -- bun run <script>
#   HOSTED_PRODUCTION=1 ... scripts/hosted.sh production -- bun run <script>
#
# DATABASE_URL is the deploy project's DATABASE_URL_DIRECT (the direct connection, never
# Hyperdrive); the storage keys come from the runtime project's /web folder; bucket, endpoint and
# region come from apps/web/wrangler.jsonc's env block, the same values the Worker uses.
# Production needs HOSTED_PRODUCTION=1, so a command meant for staging can't reach it by a typo.
# Needs `infisical login`.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "Usage: scripts/hosted.sh staging|production -- <command> [arguments]" >&2
  exit 2
}
environment="${1:-}"
shift || usage
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || usage
case "$environment" in
  staging) ;;
  production)
    [ "${HOSTED_PRODUCTION:-}" = 1 ] || {
      echo "Refusing production without HOSTED_PRODUCTION=1." >&2
      exit 2
    }
    ;;
  *) usage ;;
esac
: "${RUNTIME_PROJECT_ID:?Set RUNTIME_PROJECT_ID to the <app>-runtime-${environment} Infisical project.}"
: "${DEPLOY_PROJECT_ID:?Set DEPLOY_PROJECT_ID to the <app>-deploy-${environment} Infisical project.}"

vars="$(bun --no-env-file scripts/lib/wrangler-vars.ts apps/web/wrangler.jsonc "$environment" STORAGE_)"
while IFS= read -r line; do [ -n "$line" ] && export "${line?}"; done <<< "$vars"
export HOSTED_ENVIRONMENT="$environment"

# sslrootcert=system is for libpq; node-postgres reads it as a file path and already verifies
# against the public CAs, so it is dropped here (as in scripts/release.sh).
# shellcheck disable=SC2016 # Expanded by the inner bash, after infisical has set the secrets.
exec infisical run --silent --env=main --path=/web --projectId="$RUNTIME_PROJECT_ID" \
  -- infisical run --silent --env=main --path=/ --projectId="$DEPLOY_PROJECT_ID" \
  -- bash -c 'export DATABASE_URL="$(printf "%s" "${DATABASE_URL_DIRECT:?DATABASE_URL_DIRECT is not in the deploy project}" | sed -E "s/[&?]sslrootcert=system//")"
unset DATABASE_URL_DIRECT
exec "$@"' hosted "$@"
