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

# gci_status_emoji
check "em-success"  "🟢" "$(gci_status_emoji success)"
check "em-failed"   "🔴" "$(gci_status_emoji failed)"
check "em-running"  "🟡" "$(gci_status_emoji running)"
check "em-pending"  "🟡" "$(gci_status_emoji pending)"
check "em-other"    "⚪" "$(gci_status_emoji canceled)"

# gci_strip_ci_prefix (idempotent label cleanup)
check "strip-green"   "dbt"               "$(gci_strip_ci_prefix '🟢 dbt')"
check "strip-red"     "GQL review"        "$(gci_strip_ci_prefix '🔴 GQL review')"
check "strip-white"   "bakku-daemon"      "$(gci_strip_ci_prefix '⚪ bakku-daemon')"
check "strip-none"    "herdr"             "$(gci_strip_ci_prefix 'herdr')"
check "strip-nospace" "x"                 "$(gci_strip_ci_prefix '🟡x')"
check "strip-emoji-in-name" "my 🟢 repo"  "$(gci_strip_ci_prefix 'my 🟢 repo')"

# gci_strip_ci_prefix with the !<iid> merge-request token
check "strip-emoji-mr"   "dbt"          "$(gci_strip_ci_prefix '🟢 !123 dbt')"
check "strip-emoji-mr2"  "GQL review"   "$(gci_strip_ci_prefix '🔴 !7 GQL review')"
check "strip-mr-only"    "standalone"   "$(gci_strip_ci_prefix '!42 standalone')"
check "strip-mr-notnum"  "!abc foo"     "$(gci_strip_ci_prefix '!abc foo')"
check "strip-mr-bang"    "!important"   "$(gci_strip_ci_prefix '!important')"

# gci_hyperlink — NO_COLOR/non-tty falls back to plain text (no escape sequences)
check "hyperlink-plain"  "!123"         "$(gci_hyperlink 'https://gitlab.com/x/-/merge_requests/123' '!123')"

# gci_provider — host -> provider
check "prov-gitlab"  "gitlab" "$(gci_provider gitlab.com)"
check "prov-github"  "github" "$(gci_provider github.com)"
check "prov-gh-ent"  "github" "$(gci_provider github.acme.com)"
check "prov-self-gl" "gitlab" "$(gci_provider gitlab.example.org)"
check "prov-none"    ""       "$(gci_provider bitbucket.org)"

# gci_github_status — (status, conclusion) -> canonical status
check "gh-success"   "success"  "$(gci_github_status completed success)"
check "gh-failure"   "failed"   "$(gci_github_status completed failure)"
check "gh-timeout"   "failed"   "$(gci_github_status completed timed_out)"
check "gh-running"   "running"  "$(gci_github_status in_progress '')"
check "gh-queued"    "pending"  "$(gci_github_status queued '')"
check "gh-cancelled" "canceled" "$(gci_github_status completed cancelled)"
check "gh-skipped"   "skipped"  "$(gci_github_status completed skipped)"
check "gh-neutral"   "manual"   "$(gci_github_status completed neutral)"

# gci_strip_ci_prefix with the #<num> PR token (GitHub)
check "strip-emoji-pr"  "web app"  "$(gci_strip_ci_prefix '🟢 #42 web app')"
check "strip-pr-only"   "api"      "$(gci_strip_ci_prefix '#7 api')"
check "strip-pr-notnum" "#tag x"   "$(gci_strip_ci_prefix '#tag x')"

# gci_pane_title — provider-aware herdr pane label, derived from origin (no API call)
ptdir="$(mktemp -d)"
git -C "$ptdir" init -q 2>/dev/null
git -C "$ptdir" remote add origin 'git@github.com:acme/web-app.git' 2>/dev/null
check "title-github" "GitHub CI" "$(gci_pane_title "$ptdir")"
git -C "$ptdir" remote set-url origin 'https://gitlab.com/myteam/dbt.git' 2>/dev/null
check "title-gitlab" "GitLab CI" "$(gci_pane_title "$ptdir")"
git -C "$ptdir" remote set-url origin 'https://bitbucket.org/x/y.git' 2>/dev/null
check "title-other"  "CI"        "$(gci_pane_title "$ptdir")"
check "title-norepo" "CI"        "$(gci_pane_title "$ptdir/nonexistent")"
rm -rf "$ptdir"

exit $fail
