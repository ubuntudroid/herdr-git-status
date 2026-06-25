#!/usr/bin/env bash
# Shared helpers for the gitlab-ci-status herdr plugin. Source this file.

# Colors: empty when NO_COLOR set or stdout is not a tty.
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  GCI_RESET=$'\033[0m'; GCI_GREEN=$'\033[32m'; GCI_RED=$'\033[31m'
  GCI_YELLOW=$'\033[33m'; GCI_GRAY=$'\033[90m'; GCI_BLUE=$'\033[34m'; GCI_BOLD=$'\033[1m'
else
  GCI_RESET=''; GCI_GREEN=''; GCI_RED=''; GCI_YELLOW=''; GCI_GRAY=''; GCI_BLUE=''; GCI_BOLD=''
fi

gci_require_deps() {
  local missing=()
  for bin in glab jq git; do command -v "$bin" >/dev/null 2>&1 || missing+=("$bin"); done
  if [ ${#missing[@]} -gt 0 ]; then
    printf 'Missing dependency: %s\n' "${missing[*]}" >&2
    printf 'Install: brew install %s\n' "${missing[*]}" >&2
    return 1
  fi
}

# Load KEY=VALUE lines from <dir>/.env without overriding vars already in the
# environment (so real env vars win). <dir> defaults to $HERDR_PLUGIN_CONFIG_DIR.
gci_load_env() {
  local dir="${1:-${HERDR_PLUGIN_CONFIG_DIR:-}}" f k v
  [ -n "$dir" ] && [ -f "$dir/.env" ] || return 0
  f="$dir/.env"
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < "$f"
}

# Print "host<TAB>path" (path without trailing .git). Return 1 if not parseable.
gci_parse_remote() {
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

gci_urlencode_path() { printf '%s\n' "${1//\//%2F}"; }

gci_status_glyph() {
  case "$1" in
    success)  printf '%s' "${GCI_GREEN}✓ passed${GCI_RESET}" ;;
    failed)   printf '%s' "${GCI_RED}✗ failed${GCI_RESET}" ;;
    running)  printf '%s' "${GCI_YELLOW}● running${GCI_RESET}" ;;
    pending|created|preparing|waiting_for_resource|scheduled)
              printf '%s' "${GCI_YELLOW}● $1${GCI_RESET}" ;;
    canceled|skipped)
              printf '%s' "${GCI_GRAY}• $1${GCI_RESET}" ;;
    manual)   printf '%s' "${GCI_BLUE}⚙ manual${GCI_RESET}" ;;
    *)        printf '%s' "${1:-unknown}" ;;
  esac
}

# Relative time from ISO-8601. Optional 2nd arg = reference epoch (for tests).
gci_relative_time() {
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

# CI status -> a single colored-dot emoji (for the spaces sidebar label).
gci_status_emoji() {
  case "$1" in
    success)  printf '🟢' ;;
    failed)   printf '🔴' ;;
    running|pending|created|preparing|waiting_for_resource|scheduled)
              printf '🟡' ;;
    *)        printf '⚪' ;;
  esac
}

# Remove the CI decoration the poller prepends to a label: a leading status emoji
# (with optional following space) and then an optional "!<digits> " merge-request
# token. Byte-safe (prefix removal), so it stays idempotent across re-applies and
# user renames. Both parts are optional and stripped independently.
gci_strip_ci_prefix() {
  local rest="$1" e body num after
  for e in '🟢' '🟡' '🔴' '⚪'; do
    if [ "${rest#"$e" }" != "$rest" ]; then rest="${rest#"$e" }"; break; fi
    if [ "${rest#"$e"}"  != "$rest" ]; then rest="${rest#"$e"}";  break; fi
  done
  case "$rest" in
    '!'[0-9]*)
      body="${rest#\!}"                 # "123 dbt" or "123"
      num="${body%%[![:digit:]]*}"      # leading run of digits: "123"
      after="${body#"$num"}"            # " dbt" or ""
      case "$after" in ' '*) rest="${after# }" ;; esac
      ;;
  esac
  printf '%s' "$rest"
}

# Emit <text> as an OSC 8 terminal hyperlink to <url> (Ctrl/Cmd-clickable in modern
# terminals). Falls back to plain <text> when colors are disabled (NO_COLOR / not a
# tty), so output stays deterministic in tests and pipes.
gci_hyperlink() {
  local url="$1" text="$2"
  if [ -z "$GCI_RESET" ]; then printf '%s' "$text"; return; fi
  # BEL-terminated OSC 8 (more widely supported than the ESC-backslash ST form).
  printf '\033]8;;%s\a%s\033]8;;\a' "$url" "$text"
}

# Resolve a repo's latest pipeline for its current branch. Returns everything via
# globals (NOT stdout) so it can be called without a subshell:
#   GCI_HOST, GCI_PATH, GCI_BRANCH, GCI_ERR (on error),
#   GCI_PIPE = latest pipeline JSON object (compact), or "" when the branch has none.
# Return codes:
#   0 ok | 1 not-a-git-repo | 2 no-origin | 3 remote-not-parseable | 4 not-gitlab | 5 api-error
gci_latest_pipeline() {
  local repo="$1" url parsed enc resp
  GCI_HOST=""; GCI_PATH=""; GCI_BRANCH=""; GCI_ERR=""; GCI_PIPE=""
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 2
  parsed="$(gci_parse_remote "$url")" || return 3
  GCI_HOST="${parsed%%$'\t'*}"; GCI_PATH="${parsed#*$'\t'}"
  case "$GCI_HOST" in *gitlab*) ;; *) return 4 ;; esac
  GCI_BRANCH="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  enc="$(gci_urlencode_path "$GCI_PATH")"
  resp="$(cd "$repo" && glab api "projects/$enc/pipelines?ref=$GCI_BRANCH&per_page=1" 2>&1)" || { GCI_ERR="$resp"; return 5; }
  GCI_PIPE="$(printf '%s' "$resp" | jq -c '.[0] // empty' 2>/dev/null)"
  return 0
}

# Look up the open merge request whose source branch is <branch>. Sets globals
# (NOT stdout): GCI_MR_IID and GCI_MR_URL — both "" when there is none or on error.
# <path>/<branch> come from a prior gci_latest_pipeline call; <repo> supplies glab's
# host + auth context. Return: 0 found | 1 missing args | 2 api-error | 3 no open MR.
gci_open_mr() {
  local repo="$1" path="$2" branch="$3" enc resp
  GCI_MR_IID=""; GCI_MR_URL=""
  [ -n "$path" ] && [ -n "$branch" ] || return 1
  enc="$(gci_urlencode_path "$path")"
  resp="$(cd "$repo" && glab api "projects/$enc/merge_requests?source_branch=$branch&state=opened&per_page=1" 2>/dev/null)" || return 2
  GCI_MR_IID="$(printf '%s' "$resp" | jq -r '.[0].iid // empty' 2>/dev/null)"
  GCI_MR_URL="$(printf '%s' "$resp" | jq -r '.[0].web_url // empty' 2>/dev/null)"
  [ -n "$GCI_MR_IID" ] || { GCI_MR_IID=""; GCI_MR_URL=""; return 3; }
  return 0
}
