#!/usr/bin/env bash
# Action: resolve the current workspace's repo dir, then open the live CI pane there.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

if [ -z "$repo" ] || [ ! -d "$repo" ]; then
  printf 'gitlab-ci-status: could not resolve a repo directory from the workspace context.\n' >&2
  exit 1
fi

exec "$herdr_bin" plugin pane open \
  --plugin gitlab-ci-status \
  --entrypoint ci \
  --placement split \
  --direction right \
  --cwd "$repo" \
  --env "GITLAB_CI_REPO=$repo" \
  --focus
