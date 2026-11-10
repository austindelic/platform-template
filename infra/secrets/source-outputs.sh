#!/bin/sh
# Prints the outputs of the given roots as one JSON object, {"<source>": {"<output>": <value>}}, for
# TF_VAR_given_outputs. Each root is read with its own passphrase, from PASSPHRASE_STAGING, PASSPHRASE_PRODUCTION or
# PASSPHRASE_MONITORING; the R2 state key (AWS_*) must be in the environment, and each root already initialised.
# The output holds secret values: pass it straight into an environment variable, never to a file or the screen.
#   TF_VAR_given_output_sources='["staging","monitoring"]' TF_VAR_given_outputs="$(./source-outputs.sh staging monitoring)"
set -eu
here=$(cd "$(dirname "$0")" && pwd)
command -v jq > /dev/null || { echo "jq is needed." >&2; exit 1; }
printf '{'
sep=''
for s in "$@"; do
  case $s in
    staging | production) dir="$here/../cloud/environments/$s" ;;
    monitoring) dir="$here/../monitoring" ;;
    *) echo "Unknown source $s (staging, production or monitoring)." >&2; exit 2 ;;
  esac
  var="PASSPHRASE_$(printf %s "$s" | tr '[:lower:]' '[:upper:]')"
  eval "pass=\${$var:-}"
  [ -n "$pass" ] || { echo "Set $var to that root's state passphrase." >&2; exit 2; }
  out=$(cd "$dir" && TF_VAR_state_passphrase="$pass" tofu output -json | jq -c 'with_entries(.value = .value.value)')
  printf '%s"%s":%s' "$sep" "$s" "$out"
  sep=','
done
printf '}\n'
