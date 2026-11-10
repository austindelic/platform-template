#!/usr/bin/env sh
# Offline checks for the OpenTofu configurations (infra/cloud and the infra/* roots beside it): formatting, validation and mocked tests. Never
# reads a backend, credentials or a Cloudflare account, so it is safe in CI and in agent loops.
# Needs the committed .terraform.lock.hcl files; after changing a provider pin run
#   tofu -chdir=<dir> providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64
set -eu
cd "$(dirname "$0")"

tofu fmt -check -recursive -diff
for root in ../*/; do
  [ "$root" = ../cloud/ ] || [ "$root" = ../local/ ] && continue
  tofu fmt -check -recursive -diff "$root"
done

dirs="modules/workspace modules/access modules/credentials environments/staging environments/production"
# Sibling roots (infra/secrets, infra/monitoring) when present; infra/local holds no OpenTofu.
for root in ../*/; do
  ls "$root"*.tf > /dev/null 2>&1 && dirs="$dirs ${root%/}"
done

for dir in $dirs; do
  echo "== $dir"
  tofu -chdir="$dir" init -backend=false -lockfile=readonly -input=false > /dev/null
  tofu -chdir="$dir" validate
  if [ -d "$dir/tests" ]; then
    tofu -chdir="$dir" test
  fi
done
