#!/usr/bin/env sh
# Offline checks for the OpenTofu configuration: formatting, validation and mocked tests. Never
# reads a backend, credentials or a Cloudflare account, so it is safe in CI and in agent loops.
# Needs the committed .terraform.lock.hcl files; after changing a provider pin run
#   tofu -chdir=<dir> providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64
set -eu
cd "$(dirname "$0")"

tofu fmt -check -recursive -diff

for dir in modules/workspace modules/access environments/staging environments/production; do
  echo "== $dir"
  tofu -chdir="$dir" init -backend=false -lockfile=readonly -input=false > /dev/null
  tofu -chdir="$dir" validate
  if [ -d "$dir/tests" ]; then
    tofu -chdir="$dir" test
  fi
done
