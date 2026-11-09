#!/usr/bin/env bash
# Installs the pinned tools and workspace packages in Claude Code cloud sessions, so the agent can
# run `mise run verify` and the browser tests. Runs from the SessionStart hook in
# .claude/settings.json. Local sessions skip it. It never fails the session: problems are reported
# on stderr and the session continues without the tools.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

problem() {
  echo "Project tools not ready: $1" >&2
  exit 0
}

project="${CLAUDE_PROJECT_DIR:-$PWD}"
bin_dir="${HOME}/.local/bin"
shims="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims"
export PATH="${bin_dir}:${shims}:${PATH}"

if ! command -v mise > /dev/null; then
  command -v curl > /dev/null || problem "mise is not installed and curl is not available."
  curl -fsSL https://mise.run | MISE_QUIET=1 sh > /dev/null 2>&1 || problem "could not install mise from https://mise.run."
fi
# Only what the checks need; infisical and opentofu are for humans and the infra job.
(cd "$project" && mise trust --quiet mise.toml && mise install --quiet bun node vp) > /dev/null 2>&1 ||
  problem "mise could not install bun, node and vp. Run 'mise install bun node vp' to see why."
(cd "$project" && mise exec -- bun install --frozen-lockfile) > /dev/null 2>&1 ||
  problem "bun install --frozen-lockfile failed. Run it to see why."

deps=()
[ "$(id -u)" = 0 ] && deps=(--with-deps)
(cd "$project" && mise exec -- bunx playwright install ${deps[@]+"${deps[@]}"} chromium) > /dev/null 2>&1 ||
  echo "Chromium not installed; browser tests will not run. Try 'bunx playwright install --with-deps chromium'." >&2

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${bin_dir}:${shims}:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
echo "Project tools are ready: bun $(cd "$project" && mise exec -- bun --version)."
