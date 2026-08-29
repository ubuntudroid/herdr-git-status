#!/usr/bin/env bash
# Pane: my open PRs across all authenticated providers (GitLab via glab, GitHub via gh),
# grouped into "Ready to merge" and "Needs action".
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"
gst_load_env "${HERDR_PLUGIN_CONFIG_DIR:-$DIR}"

REPO="${GST_REPO:-$PWD}"
INTERVAL="${GST_REFRESH:-15}"
ONCE="${GST_ONCE:-}"

cleanup() { tput cnorm 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Gather classified rows from every provider we're authenticated with. Each row:
#   state \t token \t url \t project_short \t updated_at
gather_rows() {
  if command -v glab >/dev/null 2>&1; then
    gst_my_mrs_gitlab "$REPO"
  fi
  if command -v gh >/dev/null 2>&1; then
    gst_my_mrs_github "$REPO"
  fi
}

# render_section <title> ; reads TSV rows on stdin, prints the section header only if there
# is at least one row.
render_section() {
  local title="$1" any=0 state token url proj upd
  while IFS=$'\t' read -r state token url proj upd; do
    [ -n "$token" ] || continue
    if [ "$any" -eq 0 ]; then printf '\n  %s%s%s\n' "$GST_BOLD" "$title" "$GST_RESET"; any=1; fi
    printf '    %s %-7s  %-20s  %s\n' \
      "$(gst_review_glyph "$state")" "$(gst_hyperlink "$url" "$token")" "$proj" "$(gst_relative_time "$upd" 2>/dev/null)"
  done
}

build_frame() {
  gst_require_deps || { printf '%s\n' "Install jq and git to use this plugin."; return 1; }
  local rows ready action
  rows="$(gather_rows)"
  ready="$(printf  '%s\n' "$rows" | awk -F'\t' '$1=="approved"'              | sort -t$'\t' -k5,5r)"
  action="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="conflict"||$1=="changes"' | sort -t$'\t' -k5,5r)"
  printf '%s My Pull Requests%s\n' "$GST_BOLD" "$GST_RESET"
  if [ -z "${ready//[[:space:]]/}" ] && [ -z "${action//[[:space:]]/}" ]; then
    printf '\n  %sNothing needs you right now.%s\n' "$GST_GRAY" "$GST_RESET"
  else
    printf '%s\n' "$ready"  | render_section "Ready to merge"
    printf '%s\n' "$action" | render_section "Needs action"
  fi
  printf '\n  %sr%s refresh · %sq%s quit · auto-refresh %ss\n' \
    "$GST_BOLD" "$GST_RESET" "$GST_BOLD" "$GST_RESET" "$INTERVAL"
}

render() {
  local out; out="$(build_frame 2>&1)"
  clear 2>/dev/null || printf '\033[2J\033[H'
  printf '%s\n' "$out"
}

if [ -n "$ONCE" ]; then build_frame; exit 0; fi

# Name the herdr pane (overrides herdr's plugin-id fallback). HERDR_PANE_ID is set by herdr.
if [ -n "${HERDR_PANE_ID:-}" ]; then
  "${HERDR_BIN_PATH:-herdr}" pane rename "$HERDR_PANE_ID" "My PRs" >/dev/null 2>&1 || true
fi

tput civis 2>/dev/null || true
while true; do
  render
  if read -rsn1 -t "$INTERVAL" key 2>/dev/null; then
    case "$key" in q|Q) break;; r|R) :;; esac
  fi
done
