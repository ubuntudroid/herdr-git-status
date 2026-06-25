#!/usr/bin/env bash
# Pane: live GitLab project link + CI pipeline status for the current branch.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Optional config from $HERDR_PLUGIN_CONFIG_DIR/.env (only sets vars not already in env).
env_file="${HERDR_PLUGIN_CONFIG_DIR:-$DIR}/.env"
if [ -f "$env_file" ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < "$env_file"
fi

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

  if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s GitLab CI%s\n\n  Not a git repository:\n  %s\n' "$GCI_BOLD" "$GCI_RESET" "$REPO"; return 1
  fi

  local url branch parsed host path enc
  url="$(git -C "$REPO" remote get-url origin 2>/dev/null)" || {
    printf '%s GitLab CI%s\n\n  No "origin" remote in %s\n' "$GCI_BOLD" "$GCI_RESET" "$REPO"; return 1; }
  branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if ! parsed="$(gci_parse_remote "$url")"; then
    printf '%s GitLab CI%s\n\n  origin is not a parseable remote:\n  %s\n' "$GCI_BOLD" "$GCI_RESET" "$url"; return 1
  fi
  host="${parsed%%$'\t'*}"; path="${parsed#*$'\t'}"
  case "$host" in *gitlab*) ;; *)
    printf '%s GitLab CI%s\n\n  origin is not a GitLab remote:\n  %s\n' "$GCI_BOLD" "$GCI_RESET" "$url"; return 1 ;;
  esac
  enc="$(gci_urlencode_path "$path")"

  local proj_url resp pipe status web updated rel
  proj_url="https://$host/$path"
  resp="$(cd "$REPO" && glab api "projects/$enc/pipelines?ref=$branch&per_page=1" 2>&1)" || {
    printf '%s GitLab CI · %s%s\n\n  Project   %s\n  Branch    %s\n\n  %sError querying GitLab:%s\n  %s\n' \
      "$GCI_BOLD" "$host/$path" "$GCI_RESET" "$proj_url" "$branch" "$GCI_RED" "$GCI_RESET" "$resp"; return 1; }

  pipe="$(printf '%s' "$resp" | jq -r '.[0] // empty' 2>/dev/null)"
  printf '%s GitLab CI · %s%s\n\n' "$GCI_BOLD" "$host/$path" "$GCI_RESET"
  printf '  Project   %s\n' "$path"
  printf '            %s↗ %s%s\n' "$GCI_GRAY" "$proj_url" "$GCI_RESET"
  printf '  Branch    %s\n\n' "$branch"

  if [ -z "$pipe" ]; then
    printf '  Pipeline  %sNo pipelines found for %s%s\n' "$GCI_GRAY" "$branch" "$GCI_RESET"
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
