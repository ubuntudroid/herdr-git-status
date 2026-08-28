#!/usr/bin/env bash
# Always-live poller: publishes each space's CI status and MR/PR number as herdr
# sidebar metadata tokens (`ci_*`, `review_*`, `mr`). It never touches space labels or the
# agent status dot. Control: start | stop | toggle | ensure | status | poll-once | restore | run
#
# Env:
#   GITLAB_CI_REFRESH   poll interval seconds (default 30)
#   GITLAB_CI_DRYRUN    if set, print intended token reports instead of publishing them
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
# A zero/garbage interval would make consecutive cycles share one epoch second, and a
# report whose --seq repeats the last accepted one is silently dropped — so the sidebar
# would freeze rather than poll fast. Clamp to the default instead.
case "$INTERVAL" in ''|*[!0-9]*|0) INTERVAL=30 ;; esac
DRYRUN="${GITLAB_CI_DRYRUN:-}"
CYCLE_SECS=0          # duration of the last completed poll; 0 until one finishes
START_HEAL_SECS="${GITLAB_CI_START_HEAL_SECS:-5}"   # `start` watches this long, relaunching if the daemon dies
mkdir -p "$STATE_DIR" 2>/dev/null || true

# -> lines "workspace_id<TAB>label"
ws_list() {
  "$HERDR" workspace list 2>/dev/null \
    | jq -r '(.result.workspaces // .workspaces // .)[] | "\(.workspace_id)\t\(.label)"'
}

# Resolve a repo's sidebar state into globals (NOT stdout) so it can run without a
# subshell — that lets the MR/PR lookup reuse the path/branch/provider that
# gci_latest_ci just resolved:
#   SPACE_STATUS  canonical CI status, or "" (unsupported remote / nothing to say)
#   SPACE_REVIEW  canonical review state, or "" (no MR/PR)
#   SPACE_MR      open/merged MR/PR number incl. sigil ("!123" / "#123") or "" (none)
#   SPACE_SKIP    1 on a transient provider error — publish nothing this tick
# These stay CANONICAL, not display strings: gci_report_tokens turns a state into the
# token named for it, which is what lets the user colour each state separately.
# Review state is its own token, not glued to the number: they are separate facts and
# the user's rows decide whether to show one, the other, or both.
status_for_repo() {
  local cwd="$1" rc req all
  SPACE_STATUS=""; SPACE_REVIEW=""; SPACE_MR=""; SPACE_SKIP=""
  # Never inherit the previous space's merge guards (see gci_review_for_mr).
  GCI_REQUIRED_NAMES=""; GCI_REQUIRED_OPAQUE=""
  gci_latest_ci "$cwd"; rc=$?
  case $rc in
    1|2|3|4) return ;;
    5)       SPACE_SKIP=1; return ;;
    0)
      # Hold the unfiltered verdict aside. Whether it ever reaches the cell depends on
      # whether merge-guarding checks exist, which is only knowable once the PR is resolved
      # below — so SPACE_STATUS stays empty (no cell) until something earns it.
      all="$GCI_STATUS"
      # Open PR -> its review badge. No open PR (rc 3) -> it may be merged: surface a positive
      # merged badge. Missing-args/api-error (rc 1|2) -> leave empty, don't mislabel. This lives
      # here (not inside the old `if gci_open_pr`) because a merged PR returns rc 3 by definition,
      # so gluing it to the open-PR success path would make it unreachable in the case it covers.
      gci_open_pr "$cwd" "$GCI_PATH" "$GCI_BRANCH" "$GCI_PROVIDER"; rc=$?
      if [ "$rc" -eq 0 ] || { [ "$rc" -eq 3 ] && gci_merged_pr "$cwd" "$GCI_PATH" "$GCI_BRANCH" "$GCI_PROVIDER"; }; then
        [ "$rc" -eq 0 ] && gci_review_for_mr "$cwd" "$GCI_MR_PATH" "$GCI_MR_IID" "$GCI_PROVIDER"
        SPACE_REVIEW="$GCI_REVIEW"
        SPACE_MR="$GCI_MR_SIGIL$GCI_MR_IID"
        # Only merge-guarding checks decide the CI cell: a failing optional check — a lint
        # job, a coverage bot, a preview deploy — is not a reason to show the space as broken
        # when nothing is blocking the merge. Required-ness is a per-PR fact (GitHub exposes
        # it as isRequired(pullRequestNumber:)), so this narrowing only applies where a PR
        # exists; a branch with no PR has no merge to guard and every check still counts.
        if [ -n "$all" ]; then
          if [ -n "$GCI_REQUIRED_NAMES" ] && [ -n "$GCI_CI_RESP" ]; then
            # Empty result = required checks exist but none has run on this commit yet, so
            # there is no merge-guard verdict to show. Leave the cell off.
            req="$(gci_required_status "$GCI_CI_RESP" "$GCI_REQUIRED_NAMES")"
            [ -n "$req" ] && SPACE_STATUS="${req%%$'\t'*}"
          elif [ -n "$GCI_REQUIRED_OPAQUE" ]; then
            # Guards exist but cannot be filtered by name — show the unfiltered verdict
            # rather than hiding a cell that may be reporting a genuine block.
            SPACE_STATUS="$all"
          fi
        fi
      fi
      ;;
  esac
}

# Drive the loop on fd 9, NOT stdin: inner commands (herdr/glab/git) inherit stdin, and
# if the loop fed them via stdin they would consume it and truncate the loop after the
# first space. The pane list is fetched once per poll and reused for all spaces.
poll_once() {
  local panes wsid cwd seq ttl
  panes="$("$HERDR" pane list 2>/dev/null)"
  # seq is epoch seconds, NOT a per-start counter: herdr ignores a report whose seq is
  # <= the last one accepted for this (workspace, source), so a counter restarting at 0
  # would have every write after a daemon restart silently dropped. One seq per cycle is
  # enough — the next cycle is at least INTERVAL seconds later.
  seq="$(date +%s)"
  ttl="$(gci_ttl_ms "$CYCLE_SECS" "$INTERVAL")"
  while IFS=$'\t' read -r wsid _ <&9; do
    [ -n "$wsid" ] || continue
    # Resolve the space's repo from a real terminal pane, skipping plugin panes (e.g. the
    # status-bar pane, which sits on top of the layout but lives in a remote-less plugin dir).
    cwd="$(gci_pick_pane_cwd "$wsid" "$panes")"
    if [ -z "$cwd" ]; then
      SPACE_STATUS=""; SPACE_REVIEW=""; SPACE_MR=""; SPACE_SKIP=""
    else
      status_for_repo "$cwd"
    fi
    # Transient API error: publish nothing and let the already-published value ride out
    # its TTL, rather than blanking the sidebar over one failed call.
    [ -n "$SPACE_SKIP" ] && continue
    if [ -n "$DRYRUN" ]; then
      printf 'would report %s: ci=%q review=%q mr=%q (ttl %sms)\n' \
        "$wsid" "${SPACE_STATUS:-–}" "${SPACE_REVIEW:-–}" "$SPACE_MR" "$ttl"
    else
      gci_report_tokens "$wsid" "$SPACE_STATUS" "$SPACE_REVIEW" "$SPACE_MR" "$seq" "$ttl"
    fi
  done 9< <(ws_list)
}

clear_tokens() {
  local wsid seq
  seq="$(date +%s)"
  while IFS=$'\t' read -r wsid _ <&9; do
    [ -n "$wsid" ] || continue
    if [ -n "$DRYRUN" ]; then
      printf 'would clear tokens %s\n' "$wsid"
    else
      gci_clear_tokens "$wsid" "$seq"
    fi
  done 9< <(ws_list)
}

# Migration only. Earlier versions of this plugin prepended the CI dot and the MR/PR
# number to the space label; those decorations are inert now that the sidebar reads
# tokens, and nothing else would ever remove them. Idempotent, so it is safe to run on
# every daemon start as well as from `stop`/`restore`.
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

is_running() { gci_daemon_alive "$PIDFILE" "poller-ctl.sh run"; }

# Launch a detached daemon and record its pid. The run-loop takes pidfile ownership, so an
# older daemon (if any) self-exits on its next tick — this converges to a single poller.
spawn_daemon() {
  nohup bash "$DIR/poller-ctl.sh" run >>"$LOGFILE" 2>&1 </dev/null &
  echo $! > "$PIDFILE"
  disown 2>/dev/null || true
}

case "${1:-status}" in
  run)
    echo $$ > "$PIDFILE"
    trap 'exit 0' TERM INT
    restore_labels     # one-shot cleanup of decorations left by pre-token versions
    # Loop only while we remain the registered owner: `stop` removes the pidfile and
    # a newer `start` overwrites it, so any stale/duplicate daemon self-exits.
    while [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ]; do
      _t0=$SECONDS
      poll_once
      # Feeds the next cycle's self-tuned TTL. Measured, not assumed: the cycle is
      # network-bound and grows with the number of spaces.
      CYCLE_SECS=$(( SECONDS - _t0 ))
      sleep "$INTERVAL"
    done
    ;;
  start)
    # Self-healing: guarantee a live daemon by the time we return. Launch when none is
    # running, then keep watching for START_HEAL_SECS and relaunch if the daemon vanishes —
    # e.g. a one-shot `stop` racing this `start` killed it, or it died on startup. Without
    # this, a rapid stop/start could silently leave the poller stopped. A `stop` genuinely
    # issued after the window still wins (it removes the pidfile and the daemon self-exits).
    deadline=$(( SECONDS + START_HEAL_SECS ))
    while :; do
      is_running || spawn_daemon
      [ "$SECONDS" -ge "$deadline" ] && break
      sleep 1
    done
    if is_running; then echo "poller running (pid $(cat "$PIDFILE")), interval ${INTERVAL}s"
    else echo "poller failed to start" >&2; exit 1; fi
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      p="$(cat "$PIDFILE" 2>/dev/null)"; rm -f "$PIDFILE"
      if [ -n "$p" ] && gci_pid_matches "$p" "poller-ctl.sh run"; then
        kill "$p" 2>/dev/null
        # Bounded wait for graceful exit (the herdr call paces each iteration); TERM is
        # deferred while bash is mid-glab, so force-kill if it's still alive afterward.
        for _ in $(seq 1 40); do kill -0 "$p" 2>/dev/null || break; "$HERDR" workspace list >/dev/null 2>&1; done
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
      fi
    fi
    clear_tokens
    restore_labels
    echo "poller stopped; tokens cleared"
    ;;
  toggle)
    if is_running; then exec bash "$DIR/poller-ctl.sh" stop; else exec bash "$DIR/poller-ctl.sh" start; fi
    ;;
  ensure)
    # Restart only after an unexpected death: a reboot/crash leaves the pidfile
    # behind, while `stop` removes it — so deliberate stops stay stopped.
    if [ -f "$PIDFILE" ] && ! is_running; then exec bash "$DIR/poller-ctl.sh" start; fi
    ;;
  status)
    if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; fi
    ;;
  poll-once) poll_once ;;
  restore)   clear_tokens; restore_labels ;;
  *) echo "usage: poller-ctl.sh start|stop|toggle|ensure|status|poll-once|restore" >&2; exit 2 ;;
esac
