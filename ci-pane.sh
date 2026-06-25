#!/usr/bin/env bash
# Pane: live GitLab project link + CI pipeline status for the current branch.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Optional config from $HERDR_PLUGIN_CONFIG_DIR/.env (only sets vars not already in env).
gci_load_env "${HERDR_PLUGIN_CONFIG_DIR:-$DIR}"

REPO="${GITLAB_CI_REPO:-$PWD}"
INTERVAL="${GITLAB_CI_REFRESH:-15}"
ONCE="${GITLAB_CI_ONCE:-}"

cleanup() { tput cnorm 2>/dev/null || true; }
trap cleanup EXIT INT TERM

render() {
  local out
  out="$(build_frame 2>&1)"
  clear 2>/dev/null || printf '\033[2J\033[H'
  printf '%s\n' "$out"
}

build_frame() {
  gci_require_deps || { printf '%s\n' "Install glab, jq, git to use this plugin."; return 1; }

  local pipe rc
  gci_latest_pipeline "$REPO"; rc=$?; pipe="$GCI_PIPE"
  case $rc in
    1) printf '%s GitLab CI%s\n\n  Not a git repository:\n  %s\n' "$GCI_BOLD" "$GCI_RESET" "$REPO"; return 1 ;;
    2) printf '%s GitLab CI%s\n\n  No "origin" remote in %s\n' "$GCI_BOLD" "$GCI_RESET" "$REPO"; return 1 ;;
    3) printf '%s GitLab CI%s\n\n  origin is not a parseable remote.\n' "$GCI_BOLD" "$GCI_RESET"; return 1 ;;
    4) printf '%s GitLab CI%s\n\n  origin is not a GitLab remote (host: %s)\n' "$GCI_BOLD" "$GCI_RESET" "$GCI_HOST"; return 1 ;;
    5) printf '%s GitLab CI · %s%s\n\n  Branch    %s\n\n  %sError querying GitLab:%s\n  %s\n' \
         "$GCI_BOLD" "$GCI_HOST/$GCI_PATH" "$GCI_RESET" "$GCI_BRANCH" "$GCI_RED" "$GCI_RESET" "$GCI_ERR"; return 1 ;;
  esac

  local proj_url status web updated rel
  proj_url="https://$GCI_HOST/$GCI_PATH"
  printf '%s GitLab CI · %s%s\n\n' "$GCI_BOLD" "$GCI_HOST/$GCI_PATH" "$GCI_RESET"
  printf '  Project   %s\n' "$GCI_PATH"
  printf '            %s↗ %s%s\n' "$GCI_GRAY" "$proj_url" "$GCI_RESET"
  printf '  Branch    %s\n\n' "$GCI_BRANCH"

  if [ -z "$pipe" ]; then
    printf '  Pipeline  %sNo pipelines found for %s%s\n' "$GCI_GRAY" "$GCI_BRANCH" "$GCI_RESET"
  else
    status="$(printf '%s' "$pipe" | jq -r '.status // "unknown"')"
    web="$(printf '%s' "$pipe" | jq -r '.web_url // empty')"
    updated="$(printf '%s' "$pipe" | jq -r '.updated_at // empty')"
    [ -n "$updated" ] && rel="$(gci_relative_time "$updated")" || rel=""
    printf '  Pipeline  #%s   %s\n' "$(printf '%s' "$pipe" | jq -r '.id // "?"')" "$(gci_status_glyph "$status")"
    [ -n "$web" ] && printf '            %s↗ %s%s\n' "$GCI_GRAY" "$web" "$GCI_RESET"
    [ -n "$rel" ] && printf '  Updated   %s\n' "$rel"
  fi
  printf '\n  %sr%s refresh · %sq%s quit · auto-refresh %ss\n' \
    "$GCI_BOLD" "$GCI_RESET" "$GCI_BOLD" "$GCI_RESET" "$INTERVAL"
}

if [ -n "$ONCE" ]; then build_frame; exit 0; fi

tput civis 2>/dev/null || true
while true; do
  render
  if read -rsn1 -t "$INTERVAL" key 2>/dev/null; then
    case "$key" in q|Q) break;; r|R) :;; esac
  fi
done
