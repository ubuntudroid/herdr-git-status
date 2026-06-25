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
