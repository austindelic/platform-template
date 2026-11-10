#!/usr/bin/env bash
# Pushes one hosted environment's runtime secrets to its Workers, from a laptop, with
# `wrangler secret bulk` on stdin, so no value touches the disk or the terminal:
#
#   RUNTIME_PROJECT_ID=<app>-runtime-<env> DEPLOY_PROJECT_ID=<app>-deploy-<env> \
#     scripts/push-secrets.sh staging [--dry-run] [web|worker ...]
#
# Each Worker gets exactly its folder of the runtime project (/web, /worker; env main). Wrangler
# signs in with that environment's own deploy token from the deploy project. Use this where the
# Infisical Workers sync is not set up (the Free plan has 10 syncs across every repo); with the
# sync connected, the sync replaces it. Secrets the folder no longer holds stay on the Worker;
# remove one with `wrangler secret delete`. --dry-run lists names only. Production also needs
# PUSH_PRODUCTION=1. Needs `infisical login` and jq.
set -euo pipefail
cd "$(dirname "$0")/.."

environment="${1:-}"
shift || true
case "$environment" in
  staging) ;;
  production)
    [ "${PUSH_PRODUCTION:-}" = 1 ] || {
      echo "Refusing production without PUSH_PRODUCTION=1." >&2
      exit 2
    }
    ;;
  *)
    echo "Usage: scripts/push-secrets.sh staging|production [--dry-run] [web|worker ...]" >&2
    exit 2
    ;;
esac
dry_run=0
if [ "${1:-}" = --dry-run ]; then
  dry_run=1
  shift
fi
apps=("$@")
[ ${#apps[@]} -gt 0 ] || apps=(web worker)
: "${RUNTIME_PROJECT_ID:?Set RUNTIME_PROJECT_ID to the <app>-runtime-${environment} Infisical project.}"
: "${DEPLOY_PROJECT_ID:?Set DEPLOY_PROJECT_ID to the <app>-deploy-${environment} Infisical project.}"

# A JSON object of name to value for one folder, on stdout only (never printed by this script).
folder_json() {
  infisical export --silent --env=main --path="/$1" --projectId="$RUNTIME_PROJECT_ID" --format=json |
    jq -c 'if type == "array" then map({(.key): .value}) | add // {} else . end'
}

for app in "${apps[@]}"; do
  [ -f "apps/${app}/wrangler.jsonc" ] || {
    echo "No apps/${app}/wrangler.jsonc." >&2
    exit 2
  }
  names="$(folder_json "$app" | jq -r 'keys[]')"
  if [ -z "$names" ]; then
    echo "Runtime folder /${app} is empty; nothing pushed to ${app}." >&2
    continue
  fi
  echo "== ${app} (${environment}): $(printf "%s" "$names" | tr '\n' ' ')"
  [ "$dry_run" = 1 ] && continue
  folder_json "$app" | infisical run --silent --env=main --path=/ --projectId="$DEPLOY_PROJECT_ID" \
    -- bunx wrangler secret bulk --cwd "apps/${app}" --env "$environment" > /dev/null
done
[ "$dry_run" = 1 ] && echo "Dry run: names above, nothing pushed."
exit 0
