#!/usr/bin/env bash
set -u
export NO_COLOR=1                      # deterministic: no ANSI in assertions
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"; fail=1; fi
}

# gci_parse_remote — all URL shapes -> "host<TAB>path"
check "ssh-scp"     "gitlab.com	myteam/my-service" "$(gci_parse_remote 'git@gitlab.com:myteam/my-service.git')"
check "ssh-url"     "gitlab.com	myteam/my-service" "$(gci_parse_remote 'ssh://git@gitlab.com/myteam/my-service.git')"
check "https"       "gitlab.com	myteam/my-service" "$(gci_parse_remote 'https://gitlab.com/myteam/my-service.git')"
check "https-token" "gitlab.com	myteam/my-service" "$(gci_parse_remote 'https://oauth2:tok@gitlab.com/myteam/my-service.git')"
check "subgroup"    "gitlab.com	grp/sub/proj"      "$(gci_parse_remote 'git@gitlab.com:grp/sub/proj.git')"
check "no-suffix"   "gitlab.com	myteam/my-service" "$(gci_parse_remote 'https://gitlab.com/myteam/my-service')"
gci_parse_remote 'not a url' >/dev/null 2>&1; check "bad-url-returns-1" "1" "$?"

# gci_urlencode_path
check "encode"      "grp%2Fsub%2Fproj" "$(gci_urlencode_path 'grp/sub/proj')"

# gci_status_glyph (NO_COLOR -> plain text)
check "st-success"  "✓ passed"  "$(gci_status_glyph success)"
check "st-failed"   "✗ failed"  "$(gci_status_glyph failed)"
check "st-running"  "● running" "$(gci_status_glyph running)"
check "st-manual"   "⚙ manual"  "$(gci_status_glyph manual)"
check "st-unknown"  "weird"     "$(gci_status_glyph weird)"

# gci_relative_time with fixed now (ref = 2026-06-25T08:30:00 + 120s)
ref_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' '2026-06-25T08:32:00' +%s 2>/dev/null || date -u -d '2026-06-25T08:32:00' +%s)"
check "rel-2m"      "2m ago"    "$(gci_relative_time '2026-06-25T08:30:00.000Z' "$ref_epoch")"

exit $fail
