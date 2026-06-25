#!/usr/bin/env bash
# Always-live poller: reflects each space's GitLab CI status as a colored dot
# prefixed onto the space's label in the herdr sidebar. It never touches the
# agent status dot. Control: start | stop | toggle | status | poll-once | restore | run
#
# Env:
#   GITLAB_CI_REFRESH   poll interval seconds (default 30)
#   GITLAB_CI_DRYRUN    if set, print intended renames instead of applying them
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"
gci_load_env "${HERDR_PLUGIN_CONFIG_DIR:-$DIR}"

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-$DIR/.state}"
PIDFILE="$STATE_DIR/poller.pid"
LOGFILE="$STATE_DIR/poller.log"
INTERVAL="${GITLAB_CI_REFRESH:-30}"
DRYRUN="${GITLAB_CI_DRYRUN:-}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# -> lines "workspace_id<TAB>label"
ws_list() {
  "$HERDR" workspace list 2>/dev/null \
    | jq -r '(.result.workspaces // .workspaces // .)[] | "\(.workspace_id)\t\(.label)"'
}

# cwd -> emoji ("" = not a GitLab repo; "SKIP" = transient error, leave label as-is)
emoji_for_repo() {
  local cwd="$1" pipe rc st
  gci_latest_pipeline "$cwd"; rc=$?; pipe="$GCI_PIPE"
  case $rc in
    1|2|3|4) printf '' ;;
    5)       printf 'SKIP' ;;
    0)       if [ -n "$pipe" ]; then
               st="$(printf '%s' "$pipe" | jq -r '.status // "unknown"')"
               gci_status_emoji "$st"
             else
               printf '⚪'   # GitLab repo, but no pipeline for this branch
             fi ;;
  esac
}

# Drive the loop on fd 9, NOT stdin: inner commands (herdr/glab/git) inherit stdin, and
# if the loop fed them via stdin they would consume it and truncate the loop after the
# first space. The pane list is fetched once per poll and reused for all spaces.
poll_once() {
  local panes wsid label base cwd emoji new
  panes="$("$HERDR" pane list 2>/dev/null)"
  while IFS=$'\t' read -r wsid label <&9; do
    [ -n "$wsid" ] || continue
    base="$(gci_strip_ci_prefix "$label")"
    cwd="$(printf '%s' "$panes" | jq -r --arg w "$wsid" '(.result.panes // .panes // .)[] | select(.workspace_id==$w) | (.foreground_cwd // .cwd) // empty' | head -1)"
    if [ -z "$cwd" ]; then emoji=""; else emoji="$(emoji_for_repo "$cwd")"; fi
    [ "$emoji" = "SKIP" ] && continue
    if [ -n "$emoji" ]; then new="$emoji $base"; else new="$base"; fi
    [ "$new" = "$label" ] && continue
    if [ -n "$DRYRUN" ]; then
      printf 'would rename %s: %q -> %q\n' "$wsid" "$label" "$new"
    else
      "$HERDR" workspace rename "$wsid" "$new" >/dev/null 2>&1
    fi
  done 9< <(ws_list)
}

restore_labels() {
  local wsid label base
  while IFS=$'\t' read -r wsid label <&9; do
    [ -n "$wsid" ] || continue
    base="$(gci_strip_ci_prefix "$label")"
    [ "$base" = "$label" ] && continue
    if [ -n "$DRYRUN" ]; then
      printf 'would restore %s: %q -> %q\n' "$wsid" "$label" "$base"
    else
      "$HERDR" workspace rename "$wsid" "$base" >/dev/null 2>&1
    fi
  done 9< <(ws_list)
}

is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; }

case "${1:-status}" in
  run)
    echo $$ > "$PIDFILE"
    trap 'exit 0' TERM INT
    # Loop only while we remain the registered owner: `stop` removes the pidfile and
    # a newer `start` overwrites it, so any stale/duplicate daemon self-exits.
    while [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ]; do
      poll_once
      sleep "$INTERVAL"
    done
    ;;
  start)
    if is_running; then echo "poller already running (pid $(cat "$PIDFILE"))"; exit 0; fi
    nohup bash "$DIR/poller-ctl.sh" run >>"$LOGFILE" 2>&1 </dev/null &
    echo $! > "$PIDFILE"
    disown 2>/dev/null || true
    echo "poller started (pid $(cat "$PIDFILE")), interval ${INTERVAL}s"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      p="$(cat "$PIDFILE" 2>/dev/null)"; rm -f "$PIDFILE"
      if [ -n "$p" ]; then
        kill "$p" 2>/dev/null
        # Bounded wait for graceful exit (the herdr call paces each iteration); TERM is
        # deferred while bash is mid-glab, so force-kill if it's still alive afterward.
        for _ in $(seq 1 40); do kill -0 "$p" 2>/dev/null || break; "$HERDR" workspace list >/dev/null 2>&1; done
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
      fi
    fi
    restore_labels
    echo "poller stopped; labels restored"
    ;;
  toggle)
    if is_running; then exec bash "$DIR/poller-ctl.sh" stop; else exec bash "$DIR/poller-ctl.sh" start; fi
    ;;
  status)
    if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; fi
    ;;
  poll-once) poll_once ;;
  restore)   restore_labels ;;
  *) echo "usage: poller-ctl.sh start|stop|toggle|status|poll-once|restore" >&2; exit 2 ;;
esac
