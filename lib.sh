#!/usr/bin/env bash
# Shared helpers for the git-status herdr plugin. Source this file.

# Colors: empty when NO_COLOR set or stdout is not a tty.
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  GST_RESET=$'\033[0m'; GST_GREEN=$'\033[32m'; GST_RED=$'\033[31m'
  GST_YELLOW=$'\033[33m'; GST_GRAY=$'\033[90m'; GST_BLUE=$'\033[34m'; GST_BOLD=$'\033[1m'
else
  GST_RESET=''; GST_GREEN=''; GST_RED=''; GST_YELLOW=''; GST_GRAY=''; GST_BLUE=''; GST_BOLD=''
fi

# Always-required tools. The provider CLI (glab for GitLab, gh for GitHub) is
# checked per-repo in gst_latest_ci, since only one is needed for a given remote.
gst_require_deps() {
  local missing=()
  for bin in jq git; do command -v "$bin" >/dev/null 2>&1 || missing+=("$bin"); done
  if [ ${#missing[@]} -gt 0 ]; then
    printf 'Missing dependency: %s\n' "${missing[*]}" >&2
    printf 'Install: brew install %s\n' "${missing[*]}" >&2
    return 1
  fi
}

# Load KEY=VALUE lines from <dir>/.env without overriding vars already in the
# environment (so real env vars win). <dir> defaults to $HERDR_PLUGIN_CONFIG_DIR.
gst_load_env() {
  local dir="${1:-${HERDR_PLUGIN_CONFIG_DIR:-}}" f k v
  [ -n "$dir" ] && [ -f "$dir/.env" ] || return 0
  f="$dir/.env"
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < "$f"
}

# Print "host<TAB>path" (path without trailing .git). Return 1 if not parseable.
gst_parse_remote() {
  local url="$1" host path rest
  case "$url" in
    ssh://*)
      rest="${url#ssh://}"; rest="${rest#*@}"
      host="${rest%%/*}"; host="${host%%:*}"
      path="${rest#*/}" ;;
    http://*|https://*)
      rest="${url#*://}"; rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}" ;;
    *@*:*)                       # scp-like: git@host:group/proj.git
      host="${url#*@}"; host="${host%%:*}"
      path="${url#*:}" ;;
    *) return 1 ;;
  esac
  path="${path%.git}"; path="${path%/}"
  [ -n "$host" ] && [ -n "$path" ] || return 1
  printf '%s\t%s\n' "$host" "$path"
}

gst_urlencode_path() { printf '%s\n' "${1//\//%2F}"; }

# Map a remote host to a CI provider: "gitlab", "github", or "" (unsupported).
gst_provider() {
  case "$1" in
    *gitlab*) printf 'gitlab' ;;
    *github*) printf 'github' ;;
    *)        printf '' ;;
  esac
}

# Provider-aware label for the detail pane's herdr border (overrides the plugin-id
# fallback "git-status"). Derived cheaply from origin — no API call — so it is
# safe to set at pane startup: "GitLab CI", "GitHub CI", or plain "CI" otherwise.
gst_pane_title() {
  local repo="$1" url parsed host
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || { printf 'CI'; return; }
  parsed="$(gst_parse_remote "$url" 2>/dev/null)" || { printf 'CI'; return; }
  host="${parsed%%$'\t'*}"
  case "$(gst_provider "$host")" in
    gitlab) printf 'GitLab CI' ;;
    github) printf 'GitHub CI' ;;
    *)      printf 'CI' ;;
  esac
}

gst_status_glyph() {
  case "$1" in
    success)  printf '%s' "${GST_GREEN}✓ passed${GST_RESET}" ;;
    failed)   printf '%s' "${GST_RED}✗ failed${GST_RESET}" ;;
    running)  printf '%s' "${GST_YELLOW}● running${GST_RESET}" ;;
    pending|created|preparing|waiting_for_resource|scheduled)
              printf '%s' "${GST_YELLOW}● $1${GST_RESET}" ;;
    canceled|skipped)
              printf '%s' "${GST_GRAY}• $1${GST_RESET}" ;;
    manual)   printf '%s' "${GST_BLUE}⚙ manual${GST_RESET}" ;;
    *)        printf '%s' "${1:-unknown}" ;;
  esac
}

# Relative time from ISO-8601. Optional 2nd arg = reference epoch (for tests).
gst_relative_time() {
  local iso="$1" now="${2:-}" epoch base diff
  base="${iso%.*}"; base="${base%Z}"           # 2026-06-25T08:30:00
  epoch="$(date -u -d "$base" +%s 2>/dev/null \
        || date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null)" \
        || { printf '%s\n' "$iso"; return; }
  [ -n "$now" ] || now="$(date -u +%s)"
  diff=$(( now - epoch )); [ "$diff" -lt 0 ] && diff=0
  if   [ "$diff" -lt 60 ];   then printf '%ds ago\n' "$diff"
  elif [ "$diff" -lt 3600 ]; then printf '%dm ago\n' "$(( diff / 60 ))"
  elif [ "$diff" -lt 86400 ];then printf '%dh ago\n' "$(( diff / 3600 ))"
  else printf '%dd ago\n' "$(( diff / 86400 ))"; fi
}

# Canonical CI status -> one of ok | fail | run | none.
# The sidebar publishes a SEPARATE token per bucket, because herdr's token style is
# static config ({ token, fg, bold, dim }) with no conditional form: one token cannot
# change colour by state, so the state has to live in the token NAME for the user's
# rows to be able to colour it.
gst_status_bucket() {
  case "$1" in
    success)  printf 'ok' ;;
    failed)   printf 'fail' ;;
    running|pending|created|preparing|waiting_for_resource|scheduled)
              printf 'run' ;;
    *)        printf 'none' ;;
  esac
}

# CI status -> a single dot glyph. Each glyph is overridable via GST_ICON_*
# (.env or environment); a var that is set but EMPTY hides the glyph — hence
# ${VAR-default}, not ${VAR:-default}.
gst_status_emoji() {
  case "$(gst_status_bucket "$1")" in
    ok)   printf '%s' "${GST_ICON_OK-🟢}" ;;
    fail) printf '%s' "${GST_ICON_FAIL-🔴}" ;;
    run)  printf '%s' "${GST_ICON_RUN-🟡}" ;;
    *)    printf '%s' "${GST_ICON_NONE-⚪}" ;;
  esac
}

# Normalize a GitHub Actions run (.status, .conclusion) to the canonical status
# vocabulary used by gst_status_glyph / gst_status_emoji.
gst_github_status() {
  # NB: avoid a local named `status` — it is a read-only special var in zsh.
  local st="$1" cc="$2"
  if [ "$st" != "completed" ]; then
    case "$st" in
      in_progress) printf 'running' ;;
      *)           printf 'pending' ;;   # queued / waiting / requested / pending
    esac
    return
  fi
  case "$cc" in
    success)                           printf 'success' ;;
    failure|timed_out|startup_failure) printf 'failed' ;;
    cancelled|canceled)                printf 'canceled' ;;
    skipped|stale)                     printf 'skipped' ;;
    action_required|neutral)           printf 'manual' ;;
    *)                                 printf 'unknown' ;;
  esac
}

# Aggregate a head commit's GitHub check runs into one overall status. A push can trigger
# many workflows (some skip-conditioned), so sampling a single run misreports CI; the PR
# page aggregates all check runs, and so do we: the highest-severity canonical status wins
# (failed > running > pending > manual > canceled > success > unknown > skipped). Reads
# "status \t conclusion \t id \t url \t updated" lines; prints the winning run as
# "canonical \t id \t url \t updated", or nothing on empty input.
gst_github_checks_status() {
  # NB: split manually — tab is IFS whitespace, so `read` would collapse the empty
  # conclusion field of a non-completed run and shift the remaining columns.
  local line st cc rest s p best="" bp=-1 tab=$'\t'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    st="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    cc="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    s="$(gst_github_status "$st" "$cc")"
    case "$s" in
      failed) p=7 ;; running) p=6 ;; pending) p=5 ;; manual) p=4 ;;
      canceled) p=3 ;; success) p=2 ;; unknown) p=1 ;; *) p=0 ;;
    esac
    if [ "$p" -gt "$bp" ]; then bp=$p; best="$s$tab$rest"; fi
  done
  printf '%s' "$best"
}

# Canonical CI status -> the sidebar cell: "CI <glyph>". Labelling the cell means the
# glyph is not the only thing identifying what it means. A glyph hidden by a set-but-empty
# GST_ICON_* stays fully hidden — a bare "CI" with no state would be noise.
gst_ci_cell() {
  local g
  g="$(gst_status_emoji "$1")"
  [ -n "$g" ] && printf 'CI %s' "$g"
}

# Canonical review state -> glyph (full vocabulary; used by the My-PRs pane and tests).
# States: conflict | changes | draft | approved | awaiting | merged | (anything else / "") -> "".
# Overridable via GST_ICON_* like gst_status_emoji (set-but-empty hides).
gst_review_glyph() {
  case "$1" in
    conflict) printf '%s' "${GST_ICON_CONFLICT-⚠️}" ;;
    changes)  printf '%s' "${GST_ICON_CHANGES-💬}" ;;
    draft)    printf '%s' "${GST_ICON_DRAFT-📝}" ;;
    approved) printf '%s' "${GST_ICON_APPROVED-✅}" ;;
    awaiting) printf '%s' "${GST_ICON_AWAITING-👀}" ;;
    merged)   printf '%s' "${GST_ICON_MERGED-🔀}" ;;
    *)        printf '' ;;
  esac
}

# Canonical review state -> the sidebar cell: "R <glyph>". Same shape as gst_ci_cell: the
# label says which cell this is, and a glyph hidden by a set-but-empty GST_ICON_*
# stays fully hidden rather than rendering a bare "R".
gst_review_cell() {
  local g
  g="$(gst_review_glyph "$1")"
  [ -n "$g" ] && printf 'R %s' "$g"
}

# Auto-merge armed -> the sidebar cell: "A <glyph>". Unlike CI and review this is one flag,
# not a state family, so there is no "off" glyph: a PR nobody queued gets no cell at all.
# Overridable via GST_ICON_AUTOMERGE, set-but-empty hides, as everywhere else.
# Args: <"on" | anything else>
gst_automerge_cell() {
  local g
  [ "$1" = "on" ] || return 0
  g="${GST_ICON_AUTOMERGE-⏩}"
  [ -n "$g" ] && printf 'A %s' "$g"
}

# Canonical review state -> My-PRs pane section: "ready" (approved & mergeable),
# "action" (conflict or changes), or "" (not surfaced: draft/awaiting/none).
gst_mr_section() {
  case "$1" in
    approved)         printf 'ready' ;;
    conflict|changes) printf 'action' ;;
    *)                printf '' ;;
  esac
}

# GitLab MR -> canonical review state, from `detailed_merge_status` (GitLab 16.0+) with the
# MR's `blocking_discussions_resolved` flag as a fallback for statuses that don't themselves
# encode review. Returns: conflict | changes | draft | approved | awaiting | "" (no review
# owed — see the awaiting rule below).
# Args: <detailed_merge_status> [blocking_discussions_resolved: true|false] [reviewers: int]
gst_gitlab_review_state() {
  local dms="$1" blocking="${2:-true}" reviewers="${3:-0}"
  case "$dms" in
    conflict)                 printf 'conflict' ;;
    discussions_not_resolved) printf 'changes' ;;
    draft_status)             printf 'draft' ;;
    mergeable)                printf 'approved' ;;
    # Approval rules unmet: a review is owed even with no reviewer named. Unresolved
    # discussions still outrank it (changes > awaiting), as in the fallback below.
    not_approved)
      if [ "$blocking" = "false" ]; then printf 'changes'; else printf 'awaiting'; fi ;;
    *)
      # Statuses that say nothing about review (ci_must_pass, ci_still_running, …): an
      # unresolved discussion still means changes, but "awaiting" needs someone actually
      # on the hook. An MR with no reviewers assigned is awaiting nobody, so it gets no
      # glyph rather than a permanent badge.
      if [ "$blocking" = "false" ]; then printf 'changes'
      elif [ "${reviewers:-0}" -gt 0 ] 2>/dev/null; then printf 'awaiting'
      fi
      ;;
  esac
}

# blocking_discussions_resolved from a GitLab MR JSON blob, as "true"/"false". Missing or
# null still defaults to "true", but a real false must survive — jq's `//` treats false as
# falsy and would erase it, so the 'changes' fallback above could never fire.
# Args: <mr_json>
gst_gitlab_blocking_resolved() {
  printf '%s' "$1" | jq -r '.blocking_discussions_resolved | if . == null then "true" else tostring end' 2>/dev/null
}

# GitHub PR -> canonical review state, from a GraphQL pull-request projection. Precedence
# matches the badge priority (conflict > changes > draft > approved > awaiting), and "" when
# no review is owed at all.
# Args: <isDraft: true|false> <mergeable: MERGEABLE|CONFLICTING|UNKNOWN>
#       <reviewDecision: APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED|''> <unresolved_threads: int>
#       [standing_changes_reviews: int] [pending_review_requests: int]
gst_github_review_state() {
  local draft="$1" mergeable="$2" decision="$3" unresolved="${4:-0}" standing="${5:-0}" pending="${6:-0}"
  if [ "$mergeable" = "CONFLICTING" ]; then printf 'conflict'; return; fi
  # standing = CHANGES_REQUESTED entries in latestOpinionatedReviews whose author is NOT in
  # the PR's pending review requests. GitHub does NOT drop a re-requested reviewer from
  # latestOpinionatedReviews — verified live on a PR where the same login appeared in both
  # lists at once — so counting every standing entry pinned such a PR to `changes` forever
  # and made the re-request invisible. Excluding pending authors is what lets a re-request
  # hand the ball back: that reviewer's old verdict no longer stands.
  # reviewDecision is sticky across a re-request and unresolved threads outlive pushed
  # fixes, so both count only while no review is pending at all. NB: threads opened while
  # some reviewer's never-consumed initial request is pending also read as awaiting; the
  # projection can't tell fresh threads from stale ones without comparing timestamps, and
  # the pending request is the stronger signal.
  if [ "${standing:-0}" -gt 0 ] 2>/dev/null; then printf 'changes'; return; fi
  if ! { [ "${pending:-0}" -gt 0 ] 2>/dev/null; } &&
     { [ "$decision" = "CHANGES_REQUESTED" ] || [ "${unresolved:-0}" -gt 0 ] 2>/dev/null; }; then
    printf 'changes'; return
  fi
  if [ "$draft" = "true" ]; then printf 'draft'; return; fi
  if [ "$decision" = "APPROVED" ] && [ "$mergeable" = "MERGEABLE" ]; then
    printf 'approved'; return
  fi
  # "Awaiting" means a review is genuinely owed: someone is on the hook (a pending review
  # request) or GitHub itself says one is (any non-empty reviewDecision — REVIEW_REQUIRED
  # from branch protection, or a verdict that exists but lost above). A PR nobody was asked
  # to review is awaiting nobody, so it gets no glyph rather than a permanent badge.
  if [ "${pending:-0}" -gt 0 ] 2>/dev/null || [ -n "$decision" ]; then printf 'awaiting'; fi
}

# Remove the CI decoration the poller prepends to a label: a leading status emoji
# (with optional following space) and then an optional "!<digits> " (GitLab MR) or
# "#<digits> " (GitHub PR) token. Byte-safe (prefix removal), so it stays idempotent
# across re-applies and user renames. Both parts are optional, stripped independently.
gst_strip_ci_prefix() {
  local rest="$1" e body num after
  # Configured glyphs first, then the emoji defaults — so labels decorated before an
  # icon-config change still strip instead of accumulating.
  for e in "${GST_ICON_OK-}" "${GST_ICON_RUN-}" "${GST_ICON_FAIL-}" \
           "${GST_ICON_NONE-}" '🟢' '🟡' '🔴' '⚪'; do
    [ -n "$e" ] || continue      # an empty pattern would match anything
    if [ "${rest#"$e" }" != "$rest" ]; then rest="${rest#"$e" }"; break; fi
    if [ "${rest#"$e"}"  != "$rest" ]; then rest="${rest#"$e"}";  break; fi
  done
  # Optional review glyph before the MR sigil, either glued ("✅#123") or space-separated
  # ("✅ #123", how the poller emits it). Only stripped when a sigil+digit follows, so a
  # user label that merely starts with one of these emoji (e.g. "✅ done") is never clobbered.
  # The trailing "#123 " token is then removed by the sigil case below in both forms.
  for e in "${GST_ICON_CONFLICT-}" "${GST_ICON_CHANGES-}" "${GST_ICON_DRAFT-}" \
           "${GST_ICON_APPROVED-}" "${GST_ICON_AWAITING-}" "${GST_ICON_MERGED-}" \
           '⚠️' '💬' '📝' '✅' '👀' '🔀'; do
    [ -n "$e" ] || continue
    case "$rest" in
      "$e"'!'[0-9]*|"$e"'#'[0-9]*)   rest="${rest#"$e"}";  break ;;
      "$e"' !'[0-9]*|"$e"' #'[0-9]*) rest="${rest#"$e" }"; break ;;
    esac
  done
  case "$rest" in
    '!'[0-9]*|'#'[0-9]*)
      body="${rest#?}"                  # drop the sigil (! or #)
      num="${body%%[![:digit:]]*}"      # leading run of digits
      after="${body#"$num"}"
      case "$after" in ' '*) rest="${after# }" ;; esac
      ;;
  esac
  printf '%s' "$rest"
}

# Ordered cwds (foreground_cwd, else cwd) of a workspace's panes, one per line, in list order.
gst_pane_cwds() {
  local wsid="$1" panes_json="$2"
  printf '%s' "$panes_json" | jq -r --arg w "$wsid" '
    (.result.panes // .panes // .)[] | select(.workspace_id == $w) | (.foreground_cwd // .cwd) // empty
  ' 2>/dev/null
}

# True (exit 0) when <dir> is a git work tree that has an origin remote — i.e. a real project
# checkout, as opposed to a remote-less git dir like the status-bar plugin's own repo.
gst_git_has_origin() {
  local dir="$1"
  [ -n "$dir" ] || return 1
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [ -n "$(git -C "$dir" remote get-url origin 2>/dev/null)" ]
}

# Choose the cwd that represents a workspace's repo from a `herdr pane list` JSON blob.
# Prefer the first pane whose cwd is a git repo WITH an origin remote (the real project
# checkout). This skips panes like the status bar, whose cwd is a remote-less git dir and
# would otherwise shadow the repo and drop the CI dot from every space that has a bar. Panes
# whose cwd lives under the herdr plugins dir are ignored outright: an installed plugin's own
# checkout is a git repo WITH an origin remote, so the origin heuristic alone can't tell it
# from the project repo. Falls back to the first non-plugin pane when none qualifies.
# Args: <workspace_id> <pane_list_json>. Echoes the cwd, or nothing.
gst_pick_pane_cwd() {
  local wsid="$1" panes_json="$2" cwd first=""
  local plugroot="${GST_PLUGINS_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins}"
  while IFS= read -r cwd; do
    [ -n "$cwd" ] || continue
    case "$cwd" in "$plugroot"|"$plugroot"/*) continue ;; esac
    [ -n "$first" ] || first="$cwd"
    if gst_git_has_origin "$cwd"; then printf '%s\n' "$cwd"; return 0; fi
  done < <(gst_pane_cwds "$wsid" "$panes_json")
  [ -n "$first" ] && printf '%s\n' "$first"
}

# gst_pid_matches <pid> <pattern> — true when <pid> is alive AND its command line
# contains <pattern> (fixed string). Guards every pidfile consumer against pid
# reuse after a reboot: kill -0 alone cannot tell our daemon from a stranger.
gst_pid_matches() {
  ps -p "$1" -o command= 2>/dev/null | grep -qF "$2"
}

# True (exit 0) only when <pidfile> exists and names a live process. Backs the poller's
# is_running check and its self-healing `start`, which relaunches whenever this is false.
gst_daemon_alive() {
  local pidfile="$1" pattern="${2:-}" pid
  [ -f "$pidfile" ] || return 1
  pid="$(cat "$pidfile" 2>/dev/null)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [ -z "$pattern" ] && return 0
  gst_pid_matches "$pid" "$pattern"
}

# --- sidebar metadata tokens -------------------------------------------------
# The poller publishes its output as workspace metadata, not as a space label. A
# label is one shared slot, so every plugin that writes it fights every other one
# (and this plugin used to fight itself: it re-parsed its own prefix each poll).
# Tokens are namespaced per --source and cannot clobber each other.
#
# herdr renders a token only if the user's ui.sidebar.spaces.rows asks for it by name,
# and every plugin's tokens share ONE name space. Ours are prefixed "gst_" by default so
# they cannot collide with another plugin's (or with this plugin's own upstream ancestor,
# which published bare `ci_*`/`review_*`/`mr`). GST_TOKEN_PREFIX overrides the prefix;
# set it empty for bare names. Whatever it is must be mirrored in rows.
GST_CI_BUCKETS='ok fail run none'
GST_REVIEW_STATES='conflict changes draft approved awaiting merged'
gst_token_name() { printf '%s' "${GST_TOKEN_PREFIX-gst_}$1"; }

# Every token this plugin can publish, in row order.
gst_token_suffixes() {
  local b st
  for b in $GST_CI_BUCKETS;    do printf 'ci_%s\n' "$b"; done
  for st in $GST_REVIEW_STATES; do printf 'review_%s\n' "$st"; done
  printf 'pr\n'
  printf 'automerge\n'
}

# gst_report_tokens <ws_id> <ci_status> <review_state> <mr_value> <seq> <ttl_ms> [automerge]
# <ci_status> is a canonical CI status ("" = none at all); <review_state> a canonical
# review state ("" = no PR, or an open one with no review owed); <automerge> "on" when the
# PR has auto-merge armed, anything else (including omitted) when it does not.
#
# Every token goes in ONE call. --seq is tracked per (workspace, source) and a report
# whose seq is <= the last accepted one is silently ignored, so a second call in the
# same second would be lost.
#
# Both CI and review publish under the token named for their current state and send
# every sibling state EMPTY, which clears it. That is what keeps exactly one CI token
# and one review token live per space, so the user's per-state `fg` can colour them —
# herdr's token style is static config, so a single token could only have one colour.
# An empty value clearing its token is also what makes a set-but-empty
# GST_ICON_* override hide that glyph rather than render a blank slot.
gst_report_tokens() {
  local wsid="$1" status="$2" review="$3" pr="$4" seq="$5" ttl="$6" automerge="${7-}" b st bucket
  local -a args=()
  bucket=""
  [ -n "$status" ] && bucket="$(gst_status_bucket "$status")"
  for b in $GST_CI_BUCKETS; do
    if [ "$b" = "$bucket" ]; then args+=(--token "$(gst_token_name "ci_$b")=$(gst_ci_cell "$status")")
    else                         args+=(--token "$(gst_token_name "ci_$b")=")
    fi
  done
  for st in $GST_REVIEW_STATES; do
    if [ "$st" = "$review" ]; then args+=(--token "$(gst_token_name "review_$st")=$(gst_review_cell "$st")")
    else                          args+=(--token "$(gst_token_name "review_$st")=")
    fi
  done
  args+=(--token "$(gst_token_name pr)=$pr")
  args+=(--token "$(gst_token_name automerge)=$(gst_automerge_cell "$automerge")")
  "${HERDR_BIN_PATH:-herdr}" workspace report-metadata "$wsid" \
    --source git-status \
    "${args[@]}" \
    --seq "$seq" \
    --ttl-ms "$ttl" >/dev/null 2>&1
}

# gst_clear_tokens <ws_id> <seq> — drop every token now instead of waiting out the TTL.
gst_clear_tokens() {
  local sfx
  local -a args=()
  while IFS= read -r sfx; do args+=(--clear-token "$(gst_token_name "$sfx")"); done < <(gst_token_suffixes)
  "${HERDR_BIN_PATH:-herdr}" workspace report-metadata "$1" \
    --source git-status \
    "${args[@]}" \
    --seq "$2" >/dev/null 2>&1
}

# gst_ttl_ms <last_cycle_secs> <interval_secs>
# Tokens carry a TTL so a dead daemon's dots expire on their own; herdr then emits
# workspace.metadata_updated on expiry. That means the poller must republish every
# tick, not only on change, or the sidebar blanks while a repo is quiet.
#
# The TTL therefore has to outlast the republish period, which is the poll cycle
# PLUS the sleep — and the cycle is network-bound (measured 45s for 28 spaces), not
# a constant, so it cannot be a fixed number. Self-tune from the previous cycle's
# measured duration, with a floor covering the first pass (cycle unknown = 0).
# ponytail: 3x headroom absorbs a couple of skipped ticks; the cost is that a
# crashed daemon's tokens linger that long. `stop` clears them explicitly.
gst_ttl_ms() {
  local secs=$(( 3 * ($1 + $2) ))
  [ "$secs" -lt 90 ] && secs=90
  printf '%s' "$(( secs * 1000 ))"
}

# Emit <text> as an OSC 8 terminal hyperlink to <url> (Ctrl/Cmd-clickable in modern
# terminals). Falls back to plain <text> when colors are disabled (NO_COLOR / not a
# tty), so output stays deterministic in tests and pipes.
gst_hyperlink() {
  local url="$1" text="$2"
  if [ -z "$GST_RESET" ]; then printf '%s' "$text"; return; fi
  # BEL-terminated OSC 8 (more widely supported than the ESC-backslash ST form).
  printf '\033]8;;%s\a%s\033]8;;\a' "$url" "$text"
}

# Fork checkouts: print the `upstream` remote's path when one exists on the SAME host
# as origin (so provider and CLI auth context carry over); print nothing otherwise.
# Pure git-config read — no network. Forks without an `upstream` remote could fall back
# to the forge API (gh repo view --json parent / GitLab forked_from_project) — YAGNI
# until such a checkout shows up.
gst_upstream_path() {
  local repo="$1" ourl uurl op upp
  ourl="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
  uurl="$(git -C "$repo" remote get-url upstream 2>/dev/null)" || return 0
  op="$(gst_parse_remote "$ourl" 2>/dev/null)" || return 0
  upp="$(gst_parse_remote "$uurl" 2>/dev/null)" || return 0
  [ "${op%%$'\t'*}" = "${upp%%$'\t'*}" ] || return 0
  printf '%s\n' "${upp#*$'\t'}"
}

# Resolve a repo's latest CI state for its current branch, dispatching on the remote
# provider (GitLab pipelines via glab, GitHub Actions runs via gh). Returns everything
# via globals (NOT stdout) so it can be called without a subshell:
#   GST_HOST, GST_PATH, GST_BRANCH, GST_PROVIDER, GST_ERR (on error),
#   GST_STATUS  canonical status (success/failed/running/pending/canceled/skipped/
#               manual/unknown), or "" when the branch has no pipeline/run,
#   GST_CI_ID, GST_CI_URL, GST_CI_UPDATED,
#   GST_CI_PATH the repo slug the run was actually found in — fork→upstream PRs run CI
#               in the base repo (defaults to GST_PATH); pass THIS to gst_failed_ci.
# Return codes:
#   0 ok | 1 not-a-git-repo | 2 no-origin | 3 remote-not-parseable
#   4 unsupported-host (not GitLab/GitHub) | 5 api-error (incl. missing provider CLI)
gst_latest_ci() {
  local repo="$1" url parsed enc resp run up sha owner name
  GST_HOST=""; GST_PATH=""; GST_BRANCH=""; GST_PROVIDER=""; GST_ERR=""
  GST_STATUS=""; GST_CI_ID=""; GST_CI_URL=""; GST_CI_UPDATED=""; GST_CI_PATH=""; GST_CI_RESP=""
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 2
  parsed="$(gst_parse_remote "$url")" || return 3
  GST_HOST="${parsed%%$'\t'*}"; GST_PATH="${parsed#*$'\t'}"
  GST_CI_PATH="$GST_PATH"
  GST_PROVIDER="$(gst_provider "$GST_HOST")"
  [ -n "$GST_PROVIDER" ] || return 4
  GST_BRANCH="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # CI is looked up by the LOCAL HEAD COMMIT, never by branch name. A branch name resolves
  # server-side to whatever that branch points at THERE, which is a different commit
  # whenever local is ahead (unpushed work reported as green), on a detached HEAD (the ref
  # "HEAD" resolves to the repo's DEFAULT BRANCH — verified live), or in a fork whose
  # upstream has a same-named branch. All three attribute another commit's CI to this
  # checkout. A sha answers only about the commit actually checked out; if it was never
  # pushed the forge has nothing, which is the correct answer rather than a borrowed one.
  sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
  [ -n "$sha" ] || return 0

  if [ "$GST_PROVIDER" = "gitlab" ]; then
    command -v glab >/dev/null 2>&1 || { GST_ERR="glab not found — install it (brew install glab) and run: glab auth login"; return 5; }
    enc="$(gst_urlencode_path "$GST_PATH")"
    resp="$(cd "$repo" && glab api "projects/$enc/pipelines?sha=$sha&per_page=1" 2>&1)" || { GST_ERR="$resp"; return 5; }
    run="$(printf '%s' "$resp" | jq -c '.[0] // empty' 2>/dev/null)"
    # Fork→upstream MRs may run their pipelines in the target project; on no-hit, retry
    # the upstream slug (retry errors are treated as "no pipeline" — origin already answered).
    if [ -z "$run" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$GST_PATH" ]; then
      enc="$(gst_urlencode_path "$up")"
      resp="$(cd "$repo" && glab api "projects/$enc/pipelines?sha=$sha&per_page=1" 2>/dev/null)" \
        && run="$(printf '%s' "$resp" | jq -c '.[0] // empty' 2>/dev/null)" \
        && [ -n "$run" ] && GST_CI_PATH="$up" || true
    fi
    [ -n "$run" ] || return 0
    GST_STATUS="$(printf '%s' "$run" | jq -r '.status // "unknown"')"
    GST_CI_ID="$(printf '%s' "$run" | jq -r '.id // empty')"
    GST_CI_URL="$(printf '%s' "$run" | jq -r '.web_url // empty')"
    GST_CI_UPDATED="$(printf '%s' "$run" | jq -r '.updated_at // empty')"
  else
    command -v gh >/dev/null 2>&1 || { GST_ERR="gh not found — install it (brew install gh) and run: gh auth login"; return 5; }
    # Read GitHub's OWN status-check rollup for the commit rather than re-aggregating the raw
    # check-run list: the rollup is what the green tick reflects, so it already collapses
    # re-run attempts and drops suites not triggered by the push. The winning context still
    # supplies id/url/updated for the detail pane.
    owner="${GST_PATH%%/*}"; name="${GST_PATH#*/}"
    if ! resp="$(cd "$repo" && gh api graphql -f owner="$owner" -f name="$name" -f oid="$sha" -f query="$GST_ROLLUP_QUERY" 2>&1)"; then
      GST_ERR="$resp"; return 5
    fi
    # A commit the remote does not have (never pushed, or force-pushed away) comes back as a
    # null object rather than an error — that is "no CI", not a failure to report.
    run="$(printf '%s' "$resp" | jq -r --arg req "" "$GST_ROLLUP_TSV_JQ" 2>/dev/null \
      | gst_github_checks_status)"
    # Keep the response that produced $run: gst_required_status re-aggregates it with a
    # merge-guard filter, and re-fetching would double this plugin's API cost.
    GST_CI_RESP="$resp"
    # Fork PRs' `pull_request` check runs attach to the head COMMIT in the BASE repo; on
    # no-hit, retry the upstream slug (retry errors = "no run" — origin already answered).
    #
    # Same sha, different repo: it resolves upstream only when the commit is genuinely
    # shared, which is exactly the fork-PR case this retry exists for. (Retrying by branch
    # name instead reported upstream's own same-named branch as this checkout's CI — seen
    # live on a fork whose own main had no CI at all, yet showed green.)
    if [ -z "$run" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$GST_PATH" ]; then
      resp="$(cd "$repo" && gh api graphql -f owner="${up%%/*}" -f name="${up#*/}" -f oid="$sha" -f query="$GST_ROLLUP_QUERY" 2>/dev/null)" \
        && run="$(printf '%s' "$resp" | jq -r --arg req "" "$GST_ROLLUP_TSV_JQ" 2>/dev/null \
          | gst_github_checks_status)" \
        && [ -n "$run" ] && { GST_CI_PATH="$up"; GST_CI_RESP="$resp"; } || true
    fi
    [ -n "$run" ] || return 0
    IFS=$'\t' read -r GST_STATUS GST_CI_ID GST_CI_URL GST_CI_UPDATED <<<"$run"
  fi
  return 0
}

# jq program mapping a statusCheckRollup response to the TSV gst_github_checks_status reads
# ("status \t conclusion \t id \t url \t updated"), optionally filtered to $req names.
#
# The rollup is GitHub's OWN aggregation — the same set its green tick reflects — so using it
# inherits two rules this plugin used to get wrong by re-implementing them over the raw
# commits/<sha>/check-runs list: re-run attempts are collapsed to the latest per check, and
# suites whose workflow run was NOT triggered by the push are excluded. The second one
# mattered: a nightly `schedule` workflow failing against a commit turned that space red
# while GitHub showed green, because the failure says nothing about the commit.
#
# StatusContexts (legacy commit statuses) are mapped too, keyed on .context instead of .name,
# so they aggregate and filter exactly like check runs.
GST_ROLLUP_QUERY='
  query($owner:String!,$name:String!,$oid:GitObjectID!){
    repository(owner:$owner,name:$name){
      object(oid:$oid){ ... on Commit {
        statusCheckRollup { contexts(first:100){ nodes {
          __typename
          ... on CheckRun     { name    status conclusion databaseId detailsUrl completedAt startedAt }
          ... on StatusContext{ context state targetUrl createdAt }
        } } }
      } }
    }
  }'

GST_ROLLUP_TSV_JQ='
  def cell:
    if .__typename == "CheckRun" then
      [ ((.status // "") | ascii_downcase), ((.conclusion // "") | ascii_downcase),
        ((.databaseId // "") | tostring), (.detailsUrl // ""), (.completedAt // .startedAt // "") ]
    else
      [ (if (.state // "") == "PENDING" or (.state // "") == "EXPECTED" then "in_progress" else "completed" end),
        (if (.state // "") == "SUCCESS" then "success"
         elif (.state // "") == "FAILURE" or (.state // "") == "ERROR" then "failure"
         else "" end),
        "", (.targetUrl // ""), (.createdAt // "") ]
    end;
  ($req | split("\n") | map(select(length > 0))) as $names
  | (.data.repository.object.statusCheckRollup.contexts.nodes // [])
  | map(select($names == [] or ((.name // .context) as $n | ($names | index($n)) != null)))
  | .[] | cell | @tsv'

# jq program emitting one "queued" TSV row per $req name the rollup carries NO context for.
# Same column shape as GST_ROLLUP_TSV_JQ; id/url/updated are unknown, hence empty.
GST_ROLLUP_MISSING_JQ='
  ($req | split("\n") | map(select(length > 0))) as $names
  | [ (.data.repository.object.statusCheckRollup.contexts.nodes // [])[]
      | (.name // .context // empty) ] as $have
  | ($names - $have)[] | ["queued","","","",""] | @tsv'

# gst_required_status <rollup_json> <required_names>
# Re-aggregate ONLY the checks that gate merging. <required_names> is the newline-separated
# list of merge guards for the PR (see gst_required_contexts); empty means "do not filter"
# and this prints nothing, so the caller keeps the unfiltered verdict.
#
# A required name with no row in the rollup counts as PENDING, not as absent: that is
# GitHub's "Expected — waiting for status to be reported", and it blocks the merge exactly
# like a running check. Dropping it published green on a PR GitHub had BLOCKED — seen on
# Photoroom/photoroom_android#7430, whose base branch requires "🚀 Maestro Tests", a gate job
# that is only created once the maestro run it needs finishes; the commit's rollup carried
# the two guards that had already passed plus an OPTIONAL in-progress maestro job.
# Output shape matches gst_github_checks_status: "canonical \t id \t url \t updated".
gst_required_status() {
  [ -n "$2" ] || return 0
  { printf '%s' "$1" | jq -r --arg req "$2" "$GST_ROLLUP_TSV_JQ" 2>/dev/null
    printf '%s' "$1" | jq -r --arg req "$2" "$GST_ROLLUP_MISSING_JQ" 2>/dev/null
  } | gst_github_checks_status
}

# gst_required_contexts <repo> <path> <base_branch>
# Newline-separated names of the status checks the BASE branch's rules require, read from
# GitHub's effective-rules endpoint — it covers rulesets AND legacy branch protection, and
# needs no admin scope. GitHub-only: prints nothing when <base_branch> is empty (GitLab, or
# no open PR).
#
# This is the authoritative set BECAUSE it names guards that have not reported yet. The
# isRequired(pullRequestNumber:) flags gst_review_for_mr reads can only mark contexts the
# commit's rollup already carries, so a gate job created after the jobs it needs finish is
# invisible there. Callers union the two lists rather than replacing one with the other: this
# endpoint can fail on a repo whose GraphQL flags work, and losing a guard means a false green.
gst_required_contexts() {
  local repo="$1" path="$2" base="$3"
  [ -n "$path" ] && [ -n "$base" ] || return 0
  (cd "$repo" && gh api "repos/$path/rules/branches/$(gst_urlencode_path "$base")" 2>/dev/null) \
    | jq -r 'if type == "array" then
               [ .[] | select(.type == "required_status_checks")
                 | .parameters.required_status_checks[]?.context ] | unique | .[]
             else empty end' 2>/dev/null
}

# Look up the open PR whose source/head branch is <branch>, dispatching on
# <provider> ("gitlab"|"github"). Sets globals (NOT stdout): GST_PR_ID, GST_PR_URL,
# GST_PR_SIGIL ("!" for GitLab, "#" for GitHub), and GST_PR_PATH — the repo slug the
# PR was actually found in (fork→upstream PRs live in the upstream repo; pass THIS
# to gst_review_for_mr) — all "" on error/none. The args come from a prior
# gst_latest_ci call; <repo> supplies the CLI's host + auth context.
# Return: 0 found | 1 missing args | 2 api-error | 3 no open PR.
gst_open_pr() {
  local repo="$1" path="$2" branch="$3" provider="$4" enc resp owner up
  GST_PR_ID=""; GST_PR_URL=""; GST_PR_SIGIL=""; GST_PR_PATH=""
  [ -n "$path" ] && [ -n "$branch" ] || return 1
  GST_PR_PATH="$path"
  if [ "$provider" = "gitlab" ]; then
    GST_PR_SIGIL="!"
    enc="$(gst_urlencode_path "$path")"
    resp="$(cd "$repo" && glab api "projects/$enc/merge_requests?source_branch=$branch&state=opened&per_page=1" 2>/dev/null)" || return 2
    GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].iid // empty' 2>/dev/null)"
    GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].web_url // empty' 2>/dev/null)"
    # Fork→upstream MRs exist only in the TARGET project; on no-hit, retry the upstream slug.
    if [ -z "$GST_PR_ID" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$path" ]; then
      enc="$(gst_urlencode_path "$up")"
      resp="$(cd "$repo" && glab api "projects/$enc/merge_requests?source_branch=$branch&state=opened&per_page=1" 2>/dev/null)" \
        && GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].iid // empty' 2>/dev/null)" \
        && GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].web_url // empty' 2>/dev/null)" \
        && GST_PR_PATH="$up" || true
    fi
  elif [ "$provider" = "github" ]; then
    GST_PR_SIGIL="#"
    owner="${path%%/*}"
    resp="$(cd "$repo" && gh api "repos/$path/pulls?head=$owner:$branch&state=open&per_page=1" 2>/dev/null)" || return 2
    GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].number // empty' 2>/dev/null)"
    GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].html_url // empty' 2>/dev/null)"
    # Fork→upstream PRs exist only in the BASE repo; on no-hit, retry the upstream slug
    # with the same fork-qualified head filter (<fork_owner>:<branch>).
    if [ -z "$GST_PR_ID" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$path" ]; then
      resp="$(cd "$repo" && gh api "repos/$up/pulls?head=$owner:$branch&state=open&per_page=1" 2>/dev/null)" \
        && GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].number // empty' 2>/dev/null)" \
        && GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].html_url // empty' 2>/dev/null)" \
        && GST_PR_PATH="$up" || true
    fi
  else
    return 1
  fi
  [ -n "$GST_PR_ID" ] || { GST_PR_ID=""; GST_PR_URL=""; GST_PR_PATH=""; return 3; }
  return 0
}

# Look up the MERGED PR whose source/head branch is <branch>, so a positive "merged" badge
# can replace the open-PR token once gst_open_pr reports none. Same shape as gst_open_pr: sets
# globals (NOT stdout) GST_PR_ID, GST_PR_URL, GST_PR_SIGIL ("!" GitLab / "#" GitHub) — all ""
# on none/error — plus GST_REVIEW="merged" on success. GitHub's state=closed returns closed
# OR merged PRs, so merged is gated on `.merged_at != null`; GitLab's state=merged is already
# merged-only. Return: 0 merged | 1 missing args | 2 api-error | 3 not merged.
gst_merged_pr() {
  local repo="$1" path="$2" branch="$3" provider="$4" enc resp owner up
  # GST_AUTOMERGE resets here too: the poller reaches this function INSTEAD of
  # gst_review_for_mr when the PR is already merged, so nothing else would clear the
  # previous space's badge on a merged space.
  GST_PR_ID=""; GST_PR_URL=""; GST_PR_SIGIL=""; GST_PR_PATH=""; GST_REVIEW=""; GST_AUTOMERGE=""
  [ -n "$path" ] && [ -n "$branch" ] || return 1
  GST_PR_PATH="$path"
  if [ "$provider" = "gitlab" ]; then
    GST_PR_SIGIL="!"
    enc="$(gst_urlencode_path "$path")"
    resp="$(cd "$repo" && glab api "projects/$enc/merge_requests?source_branch=$branch&state=merged&per_page=1" 2>/dev/null)" || return 2
    GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].iid // empty' 2>/dev/null)"
    GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].web_url // empty' 2>/dev/null)"
    # Fork→upstream MRs merge in the TARGET project; on no-hit, retry the upstream slug.
    if [ -z "$GST_PR_ID" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$path" ]; then
      enc="$(gst_urlencode_path "$up")"
      resp="$(cd "$repo" && glab api "projects/$enc/merge_requests?source_branch=$branch&state=merged&per_page=1" 2>/dev/null)" \
        && GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].iid // empty' 2>/dev/null)" \
        && GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].web_url // empty' 2>/dev/null)" \
        && [ -n "$GST_PR_ID" ] && GST_PR_PATH="$up" || true
    fi
  elif [ "$provider" = "github" ]; then
    GST_PR_SIGIL="#"
    owner="${path%%/*}"
    resp="$(cd "$repo" && gh api "repos/$path/pulls?head=$owner:$branch&state=closed&per_page=1" 2>/dev/null)" || return 2
    if [ -n "$(printf '%s' "$resp" | jq -r '.[0].merged_at // empty' 2>/dev/null)" ]; then
      GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].number // empty' 2>/dev/null)"
      GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].html_url // empty' 2>/dev/null)"
    fi
    # Fork→upstream PRs merge in the BASE repo; on no-hit, retry the upstream slug with the
    # same fork-qualified head filter (<fork_owner>:<branch>), still gated on .merged_at.
    if [ -z "$GST_PR_ID" ] && up="$(gst_upstream_path "$repo")" && [ -n "$up" ] && [ "$up" != "$path" ]; then
      resp="$(cd "$repo" && gh api "repos/$up/pulls?head=$owner:$branch&state=closed&per_page=1" 2>/dev/null)" || resp=""
      if [ -n "$(printf '%s' "$resp" | jq -r '.[0].merged_at // empty' 2>/dev/null)" ]; then
        GST_PR_ID="$(printf '%s' "$resp" | jq -r '.[0].number // empty' 2>/dev/null)"
        GST_PR_URL="$(printf '%s' "$resp" | jq -r '.[0].html_url // empty' 2>/dev/null)"
        [ -n "$GST_PR_ID" ] && GST_PR_PATH="$up"
      fi
    fi
  else
    return 1
  fi
  [ -n "$GST_PR_ID" ] || { GST_PR_ID=""; GST_PR_URL=""; GST_PR_PATH=""; return 3; }
  GST_REVIEW="merged"
  return 0
}

# Resolve the canonical review state of a single open PR. Network call; dispatches on
# <provider>. Sets GST_REVIEW to conflict|changes|draft|approved|awaiting, or "" when no
# review is owed (nobody requested one) and on any error/missing data — callers fall back
# to no glyph in both cases. <repo> supplies CLI auth/host context.
# For GitLab, <path> may be a urlencodable project path OR a numeric project id (both work
# with the projects/:id/merge_requests/:iid endpoint). For GitHub, <path> is "owner/name".
# Args: repo path iid provider
gst_review_for_mr() {
  local repo="$1" path="$2" iid="$3" provider="$4"
  local enc resp dms blocking reviewers draft mergeable decision unresolved standing pending owner name
  GST_REVIEW=""
  # Reset alongside GST_REVIEW: the poller calls this per space in a loop, and a space with
  # no PR must never inherit the previous space's required set — two worktrees of the same
  # repo would have matching check names, so a sibling PR's guards would silently filter it.
  # GST_PR_BASE (the PR's target branch, GitHub only) is the ref whose rules name the guards.
  # GST_AUTOMERGE ("on" / "") is per-PR the same way and would otherwise stick to every
  # later space in the loop.
  GST_REQUIRED_NAMES=""; GST_PR_BASE=""; GST_AUTOMERGE=""
  [ -n "$path" ] && [ -n "$iid" ] || return 0
  if [ "$provider" = "gitlab" ]; then
    enc="$(gst_urlencode_path "$path")"
    resp="$(cd "$repo" && glab api "projects/$enc/merge_requests/$iid" 2>/dev/null)" || return 0
    dms="$(printf '%s' "$resp" | jq -r '.detailed_merge_status // empty' 2>/dev/null)"
    [ -n "$dms" ] || return 0
    blocking="$(gst_gitlab_blocking_resolved "$resp")"
    reviewers="$(printf '%s' "$resp" | jq -r '(.reviewers // []) | length' 2>/dev/null)"
    GST_REVIEW="$(gst_gitlab_review_state "$dms" "$blocking" "${reviewers:-0}")"
    # GitLab's auto-merge is "merge when pipeline succeeds" (merge trains set the same flag).
    # `// empty` would be wrong: jq treats false as falsy, so a disarmed MR would read as
    # missing rather than off — harmless here, but tostring keeps the two distinguishable.
    [ "$(printf '%s' "$resp" | jq -r '.merge_when_pipeline_succeeds | tostring' 2>/dev/null)" = "true" ] \
      && GST_AUTOMERGE="on"
  elif [ "$provider" = "github" ]; then
    owner="${path%%/*}"; name="${path#*/}"
    resp="$(cd "$repo" && gh api graphql -f owner="$owner" -f name="$name" -F number="$iid" -f query='
      query($owner:String!,$name:String!,$number:Int!){
        repository(owner:$owner,name:$name){
          pullRequest(number:$number){
            baseRefName
            isDraft
            mergeable
            reviewDecision
            autoMergeRequest { enabledAt }
            reviewThreads(first:100){ nodes { isResolved } }
            reviewRequests(first:100){ totalCount nodes { requestedReviewer { ... on User { login } } } }
            latestOpinionatedReviews(first:100){ nodes { state author { login } } }
            commits(last:1){ nodes { commit { statusCheckRollup { contexts(first:100){ nodes {
              __typename
              ... on CheckRun     { name    isRequired(pullRequestNumber:$number) }
              ... on StatusContext{ context isRequired(pullRequestNumber:$number) }
            } } } } } }
          }
        }
      }' 2>/dev/null)" || return 0
    # NB: `// empty` would erase isDraft:false (jq treats false as falsy); only bail on a missing PR.
    draft="$(printf '%s' "$resp" | jq -r 'if .data.repository.pullRequest == null then empty else (.data.repository.pullRequest.isDraft|tostring) end' 2>/dev/null)"
    [ -n "$draft" ] || return 0
    mergeable="$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.mergeable // "UNKNOWN"' 2>/dev/null)"
    decision="$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.reviewDecision // ""' 2>/dev/null)"
    unresolved="$(printf '%s' "$resp" | jq -r '[.data.repository.pullRequest.reviewThreads.nodes[]? | select(.isResolved==false)] | length' 2>/dev/null)"
    # Only verdicts from reviewers who are NOT pending again: a re-request retires the old one.
    standing="$(printf '%s' "$resp" | jq -r '
      .data.repository.pullRequest as $p
      | (($p.reviewRequests.nodes // []) | map(.requestedReviewer.login // empty)) as $pend
      | [ (($p.latestOpinionatedReviews.nodes // [])[]
           | select(.state == "CHANGES_REQUESTED")
           | (.author.login // "") as $a
           | select(($pend | index($a)) == null) ) ]
      | length' 2>/dev/null)"
    pending="$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.reviewRequests.totalCount // 0' 2>/dev/null)"
    GST_REVIEW="$(gst_github_review_state "$draft" "$mergeable" "$decision" "${unresolved:-0}" "${standing:-0}" "${pending:-0}")"
    # Auto-merge armed: GitHub exposes it as a non-null autoMergeRequest on the PR. Null (or
    # absent, on an older projection) means nobody queued it.
    [ -n "$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.autoMergeRequest // empty' 2>/dev/null)" ] \
      && GST_AUTOMERGE="on"
    GST_PR_BASE="$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.baseRefName // empty' 2>/dev/null)"
    # Names of the checks that actually gate merging, for gst_required_status. Legacy commit
    # statuses are keyed on .context rather than .name and are included: the CI verdict now
    # comes from the same statusCheckRollup, which carries them, so a required status filters
    # like any check run instead of having to disable filtering to stay safe.
    # This list only covers guards the rollup ALREADY carries — callers union it with
    # gst_required_contexts "$GST_PR_BASE" to also see the ones still waiting to report.
    GST_REQUIRED_NAMES="$(printf '%s' "$resp" | jq -r '
      [ (.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // [])[]
        | select(.isRequired == true) | (.name // .context // empty) ] | join("\n")' 2>/dev/null)"
  fi
  return 0
}

# List MY open MRs across all GitLab projects, classified by review state. Emits TSV rows:
#   state \t !<iid> \t web_url \t project_short \t updated_at
# <repo> supplies glab auth/host context (defaults to $PWD). No-op (prints nothing) if glab
# is missing or the current user can't be resolved.
gst_my_mrs_gitlab() {
  local repo="${1:-$PWD}" me resp pid iid url upd proj
  command -v glab >/dev/null 2>&1 || return 0
  me="$(cd "$repo" && glab api user 2>/dev/null | jq -r '.username // empty')"
  [ -n "$me" ] || return 0
  resp="$(cd "$repo" && glab api "merge_requests?author_username=$me&state=opened&scope=all&per_page=50" 2>/dev/null)" || return 0
  while IFS=$'\t' read -r pid iid url upd; do
    [ -n "$iid" ] || continue
    gst_review_for_mr "$repo" "$pid" "$iid" "gitlab"
    proj="${url#https://}"; proj="${proj#*/}"; proj="${proj%%/-/*}"; proj="${proj##*/}"
    printf '%s\t!%s\t%s\t%s\t%s\n' "$GST_REVIEW" "$iid" "$url" "$proj" "$upd"
  done < <(printf '%s' "$resp" | jq -r '.[] | [(.project_id|tostring), (.iid|tostring), .web_url, (.updated_at // .created_at)] | @tsv' 2>/dev/null)
}

# List MY open PRs across all GitHub repos, classified by review state. Emits TSV rows:
#   state \t #<num> \t html_url \t repo_name \t updated_at
# <repo> supplies gh auth/host context (defaults to $PWD). No-op if gh is missing.
gst_my_mrs_github() {
  local repo="${1:-$PWD}" resp owner name num url upd
  command -v gh >/dev/null 2>&1 || return 0
  resp="$(cd "$repo" && gh search prs --author=@me --state=open --limit 50 --json number,url,repository,updatedAt 2>/dev/null)" || return 0
  while IFS=$'\t' read -r owner name num url upd; do
    [ -n "$num" ] || continue
    gst_review_for_mr "$repo" "$owner/$name" "$num" "github"
    printf '%s\t#%s\t%s\t%s\t%s\n' "$GST_REVIEW" "$num" "$url" "$name" "$upd"
  done < <(printf '%s' "$resp" | jq -r '.[] | [(.repository.nameWithOwner|split("/")[0]), (.repository.nameWithOwner|split("/")[1]), (.number|tostring), .url, .updatedAt] | @tsv' 2>/dev/null)
}

# Stream recent FAILED pipelines/runs for <branch> (newest first), up to <limit> lines of
#   <id>\t<web_url>\t<updated_at>
# Args: repo path branch provider [limit]. <repo> supplies the CLI's host + auth context.
# Empty output = no failures, or a transient API/CLI error (treated as "none" — hard errors
# are already surfaced by gst_latest_ci, which build_frame checks before calling this).
gst_failed_ci() {
  local repo="$1" path="$2" branch="$3" provider="$4" limit="${5:-5}" enc
  [ -n "$path" ] && [ -n "$branch" ] || return 0
  if [ "$provider" = "gitlab" ]; then
    enc="$(gst_urlencode_path "$path")"
    (cd "$repo" && glab api "projects/$enc/pipelines?ref=$branch&status=failed&per_page=$limit" 2>/dev/null) \
      | jq -r '.[] | "\(.id)\t\(.web_url)\t\(.updated_at // .created_at)"' 2>/dev/null
  elif [ "$provider" = "github" ]; then
    (cd "$repo" && gh api "repos/$path/actions/runs?branch=$branch&status=failure&per_page=$limit" 2>/dev/null) \
      | jq -r '.workflow_runs[] | "\(.id)\t\(.html_url)\t\(.updated_at // .created_at)"' 2>/dev/null
  fi
}
