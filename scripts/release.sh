#!/usr/bin/env bash
# Deploys one hosted environment, in order: database migrations over the direct connection
# (never through Hyperdrive), the jobs Worker, then the web Worker (it binds to the jobs Worker,
# so that one goes first). OpenTofu changes are applied by hand beforehand (infra/cloud/README.md).
#
#   scripts/release.sh staging|production      (or: mise run release staging)
#
# Run by .github/workflows/deploy.yml, or by hand after `infisical login`. Secrets come from the
# environment's <app>-deploy-<env> Infisical project and are passed to each command, never written
# to disk: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID and DATABASE_URL_DIRECT. In CI,
# Infisical/secrets-action has already exported them and SECRETS_FROM_ENV=1 says so. By hand, set
# INFISICAL_PROJECT_ID to the <app>-deploy-<env> project. With RELEASE_HEALTH_URL set (for example
# https://app.example.com/healthz) the release fails unless that URL answers 200 "ok" afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

environment="${1:-}"
case "$environment" in
  staging | production) ;;
  *)
    echo "Usage: scripts/release.sh staging|production" >&2
    exit 2
    ;;
esac
# Each Infisical project has one environment, slug main (infra/cloud/README.md).
secrets_env=main
apps=(worker web)

with_secrets() {
  if [ "${SECRETS_FROM_ENV:-}" = 1 ]; then
    "$@"
    return
  fi
  infisical run --silent --env="$secrets_env" \
    ${INFISICAL_PROJECT_ID:+--projectId="$INFISICAL_PROJECT_ID"} \
    -- "$@"
}

# Each Worker needs its hosted Wrangler environment, with every placeholder filled
# (infra/cloud/README.md, step 5).
for app in "${apps[@]}"; do
  config="apps/${app}/wrangler.jsonc"
  if ! grep -Eq "\"${environment}\"[[:space:]]*:[[:space:]]*\{" "$config"; then
    echo "${config} has no \"${environment}\" environment yet (infra/cloud/README.md, step 5)." >&2
    exit 1
  fi
  if grep -n "REPLACE_WITH_" "$config" | grep -qi "${environment}"; then
    echo "${config} still has REPLACE_WITH_ placeholders for ${environment}:" >&2
    grep -n "REPLACE_WITH_" "$config" | grep -i "${environment}" >&2
    exit 1
  fi
done

version="${GITHUB_SHA:-$(git rev-parse HEAD)}"
message="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)} ${version:0:12}"

# Migrations must only add, so the Workers still running keep working while they apply.
echo "== migrations (${environment})"
# shellcheck disable=SC2016 # Expanded by the inner shell, inside with_secrets.
with_secrets sh -c '
  if [ -z "${DATABASE_URL_DIRECT:-}" ]; then
    echo "DATABASE_URL_DIRECT is not set in the deploy project; skipping migrations." >&2
    exit 0
  fi
  DATABASE_URL="$DATABASE_URL_DIRECT" bun run db:migrate
'

echo "== worker (${environment})"
(cd apps/worker && with_secrets bunx wrangler deploy --env "$environment" --tag "${version:0:12}" --message "$message")

echo "== web (${environment})"
(cd apps/web && bun run build && with_secrets bunx wrangler deploy --env "$environment" --tag "${version:0:12}" --message "$message")

if [ -n "${RELEASE_HEALTH_URL:-}" ]; then
  echo "== health (${RELEASE_HEALTH_URL})"
  for attempt in 1 2 3 4 5 6; do
    body="$(curl -fsS --max-time 10 "$RELEASE_HEALTH_URL" 2> /dev/null || true)"
    if [ "$body" = "ok" ]; then
      echo "Healthy after ${attempt} attempt(s)."
      break
    fi
    if [ "$attempt" = 6 ]; then
      echo "${RELEASE_HEALTH_URL} did not answer ok (an Access login page means /healthz needs a bypass path)." >&2
      exit 1
    fi
    sleep 10
  done
fi

echo "Deployed ${message} to ${environment}."
