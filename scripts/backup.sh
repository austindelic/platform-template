#!/usr/bin/env bash
# shellcheck disable=SC2016 # The single-quoted scripts below run in an inner bash, after with_secrets sets their variables.
# Backups for one hosted environment (infra/cloud/README.md, Backups):
#
#   scripts/backup.sh dump    staging|production   encrypted pg_dump to the locked R2 backups bucket
#   scripts/backup.sh copy    staging|production   rclone the R2 buckets to the versioned B2 bucket
#   scripts/backup.sh restore staging|production   restore the latest dump into a throwaway Postgres
#
# dump and copy are run by .github/workflows/backups.yml with a CI identity that reads only the Infisical project
# <app>-backups-prod (one environment, slug "main"). restore is run by a person: it needs the age PRIVATE key, which
# is in no Infisical project and which no CI identity can read. Needs docker, rclone and age, and these from that
# project (passed to each command, never written to disk):
#   DATABASE_URL_DIRECT                     Direct (not Hyperdrive) connection string for a read-only backup
#                                           role (modules/credentials mints one on PlanetScale)
#   BACKUP_AGE_RECIPIENTS                   age PUBLIC keys, space-separated; the dump needs nothing else. The
#                                           private halves live in the password manager and on paper
#   BACKUP_R2_ENDPOINT, BACKUP_R2_ACCESS_KEY_ID, BACKUP_R2_SECRET_ACCESS_KEY
#                                           R2 token: read on the storage bucket, write on backups
#   BACKUP_B2_KEY_ID, BACKUP_B2_APPLICATION_KEY, BACKUP_B2_BUCKET
#                                           B2 application key for the copy bucket only, in a
#                                           separate Backblaze account, with versioning, Object Lock and a
#                                           lifecycle. Without BACKUP_B2_BUCKET, copy is skipped
#   BACKUP_B2_ENDPOINT                      optional: an S3 endpoint instead of the native B2 API,
#                                           only for a local test against S3-compatible storage
#   BACKUP_AGE_IDENTITY_FILE                restore only, set in your shell: path to the age private key file
#                                           (from the password manager); never read from Infisical
#   BACKUP_HEARTBEAT_URL_DUMP|COPY|RESTORE  optional Better Stack heartbeat per job, pinged at the end of a
#                                           successful run and at <url>/fail on failure
# PG_MAJOR (default 18) picks the Postgres image, which must match the server's major version. RESTORE_CHECK_SQL
# (default: the example items table) is a query whose result the restore test prints, proving data came back.
set -euo pipefail
cd "$(dirname "$0")/.."

job="${1:-}"
environment="${2:-}"
case "$environment" in
  staging | production) ;;
  *)
    echo "Usage: scripts/backup.sh dump|copy|restore staging|production" >&2
    exit 2
    ;;
esac
# Bucket names from infra/cloud/modules/workspace: <project>-<env> and <project>-backups-<env>.
storage_bucket="${BACKUP_STORAGE_BUCKET:-platform-starter-${environment}}"
backups_bucket="${BACKUP_BACKUPS_BUCKET:-platform-starter-backups-${environment}}"
export PG_IMAGE="postgres:${PG_MAJOR:-18}"
export STORAGE_BUCKET="$storage_bucket" BACKUPS_BUCKET="$backups_bucket" ENVIRONMENT="$environment"
export RESTORE_CHECK_SQL="${RESTORE_CHECK_SQL:-select count(*) from items}"
# The Postgres image has no CA certificates, so sslrootcert=system can't verify the database's
# certificate. The host's bundle (Linux or macOS) is mounted where its OpenSSL looks.
for bundle in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
  if [ -s "$bundle" ]; then
    export CA_BUNDLE="$bundle"
    break
  fi
done
: "${CA_BUNDLE:?No CA bundle found on this machine for the database TLS check.}"

# SECRETS_FROM_ENV=1 reads the variables from the environment instead: in CI, where Infisical/secrets-action put them
# there over GitHub OIDC, or for a local test run.
with_secrets() {
  if [ "${SECRETS_FROM_ENV:-}" = 1 ]; then
    bash -euo pipefail -c "$1"
    return
  fi
  infisical run --silent --env="${INFISICAL_ENV:-main}" \
    ${INFISICAL_PROJECT_ID:+--projectId="$INFISICAL_PROJECT_ID"} \
    ${INFISICAL_TOKEN:+--token="$INFISICAL_TOKEN"} \
    -- bash -euo pipefail -c "$1"
}

# rclone remotes come from environment variables, so no config file holds a key.
remotes='
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ENDPOINT="$BACKUP_R2_ENDPOINT"
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$BACKUP_R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$BACKUP_R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
# The native B2 API: deletes hide a file instead of removing it, so with versioning and Object
# Lock every earlier version stays until the lifecycle rule and the lock both allow removal.
if [ -n "${BACKUP_B2_ENDPOINT:-}" ]; then
  export RCLONE_CONFIG_B2_TYPE=s3 RCLONE_CONFIG_B2_PROVIDER=Other
  export RCLONE_CONFIG_B2_ENDPOINT="$BACKUP_B2_ENDPOINT"
  export RCLONE_CONFIG_B2_ACCESS_KEY_ID="$BACKUP_B2_KEY_ID"
  export RCLONE_CONFIG_B2_SECRET_ACCESS_KEY="$BACKUP_B2_APPLICATION_KEY"
  export RCLONE_CONFIG_B2_NO_CHECK_BUCKET=true
else
  export RCLONE_CONFIG_B2_TYPE=b2
  export RCLONE_CONFIG_B2_ACCOUNT="$BACKUP_B2_KEY_ID"
  export RCLONE_CONFIG_B2_KEY="$BACKUP_B2_APPLICATION_KEY"
  export RCLONE_CONFIG_B2_HARD_DELETE=false
fi
heartbeat() {
  local url_var="BACKUP_HEARTBEAT_URL_$1"
  if [ -n "${!url_var:-}" ]; then curl -fsS -m 10 --retry 3 "${!url_var}${2:-}" > /dev/null || true; fi
}
'

case "$job" in
  dump)
    with_secrets "$remotes"'
      stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
      file="$(mktemp -d)/${BACKUPS_BUCKET}-${stamp}.dump.age"
      recipients=()
      for key in $BACKUP_AGE_RECIPIENTS; do recipients+=(--recipient "$key"); done
      docker run --rm -e PGCONNECT_TIMEOUT=20 -v "$CA_BUNDLE:/etc/ssl/certs/ca-certificates.crt:ro" "$PG_IMAGE" \
        pg_dump --format=custom --no-owner --no-privileges "$DATABASE_URL_DIRECT" \
        | age --encrypt "${recipients[@]}" > "$file"
      test -s "$file"
      rclone copyto "$file" "r2:${BACKUPS_BUCKET}/daily/$(basename "$file")"
      # The first dump of each month is also kept for a year.
      if [ "$(date -u +%d)" = "01" ]; then
        rclone copyto "$file" "r2:${BACKUPS_BUCKET}/monthly/$(basename "$file")"
      fi
      echo "Dumped $(du -h "$file" | cut -f1) to ${BACKUPS_BUCKET}/daily/."
      heartbeat DUMP
    ' || { with_secrets "$remotes"'heartbeat DUMP /fail'; exit 1; }
    ;;
  copy)
    with_secrets "$remotes"'
      if [ -z "${BACKUP_B2_BUCKET:-}" ]; then
        echo "BACKUP_B2_BUCKET is not set: no second copy to make." >&2
        exit 0
      fi
      # --max-delete stops a mass delete in R2 from emptying the copy in one run; B2 keeps
      # deleted and overwritten files as hidden versions for 90 days. R2 (MD5) and B2 (SHA-1)
      # share no hash, and keys are never reused, so files are matched by size and time.
      for bucket in "$STORAGE_BUCKET" "$BACKUPS_BUCKET"; do
        rclone sync "r2:${bucket}" "b2:${BACKUP_B2_BUCKET}/${bucket}" \
          --max-delete 200 --transfers 8 --stats-one-line --stats 60s
      done
      heartbeat COPY
    ' || { with_secrets "$remotes"'heartbeat COPY /fail'; exit 1; }
    ;;
  restore)
    : "${BACKUP_AGE_IDENTITY_FILE:?Set BACKUP_AGE_IDENTITY_FILE to the age private key file (password manager). CI never has it.}"
    test -r "$BACKUP_AGE_IDENTITY_FILE" || { echo "Cannot read $BACKUP_AGE_IDENTITY_FILE." >&2; exit 2; }
    export BACKUP_AGE_IDENTITY_FILE
    with_secrets "$remotes"'
      latest="$(rclone lsf "r2:${BACKUPS_BUCKET}/daily/" | sort | tail -1)"
      test -n "$latest" || { echo "No dumps in ${BACKUPS_BUCKET}/daily/." >&2; exit 1; }
      work="$(mktemp -d)"
      rclone copyto "r2:${BACKUPS_BUCKET}/daily/${latest}" "${work}/dump.age"
      age --decrypt --identity "$BACKUP_AGE_IDENTITY_FILE" "${work}/dump.age" > "${work}/dump"
      name="restore-test-$$"
      docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=restore-test "$PG_IMAGE" > /dev/null
      trap "docker stop $name > /dev/null 2>&1 || true; rm -rf $work" EXIT
      # The image first runs a temporary server for initdb, shuts it down and then starts the real one, and pg_isready
      # answers during the temporary one. Wait for the init to finish, then for the real server.
      until docker logs "$name" 2>&1 | grep -q "PostgreSQL init process complete"; do sleep 1; done
      until docker exec "$name" pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
      # PlanetScale extensions (hypopg and others, schema pscale_extensions) are missing from plain
      # Postgres, and the app creates none, so the test restore leaves out every extension; the
      # dump itself keeps them for a restore to PlanetScale.
      docker cp "${work}/dump" "$name:/tmp/dump" > /dev/null
      docker exec "$name" sh -c "pg_restore -l /tmp/dump | grep -vE \"pscale_extensions|EXTENSION\" > /tmp/list"
      docker exec "$name" pg_restore --exit-on-error --no-owner --no-privileges -U postgres -d postgres -L /tmp/list /tmp/dump
      query() { docker exec "$name" psql -U postgres -d postgres -Atc "$1"; }
      echo "Restored ${latest}. ${RESTORE_CHECK_SQL}: $(query "$RESTORE_CHECK_SQL")"
      # The nightly dump must be from today or yesterday (UTC), or the dump job has stopped.
      day="$(printf "%s" "$latest" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1)"
      # GNU date (CI) takes -d yesterday, BSD date (macOS laptops, where restores run) takes -v-1d.
      yesterday="$(date -u -d yesterday +%F 2> /dev/null || date -u -v-1d +%F)"
      if [ "$day" != "$(date -u +%F)" ] && [ "$day" != "$yesterday" ]; then
        echo "The newest dump is from ${day:-an unknown day}; the nightly dump has stopped." >&2
        exit 1
      fi
      heartbeat RESTORE
    ' || { with_secrets "$remotes"'heartbeat RESTORE /fail'; exit 1; }
    ;;
  *)
    echo "Usage: scripts/backup.sh dump|copy|restore staging|production" >&2
    exit 2
    ;;
esac
