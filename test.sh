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

# gci_review_glyph — full canonical vocabulary -> emoji
check "rg-conflict" "⚠️" "$(gci_review_glyph conflict)"
check "rg-changes"  "💬" "$(gci_review_glyph changes)"
check "rg-draft"    "📝" "$(gci_review_glyph draft)"
check "rg-approved" "✅" "$(gci_review_glyph approved)"
check "rg-awaiting" "👀" "$(gci_review_glyph awaiting)"
check "rg-none"     ""   "$(gci_review_glyph none)"
check "rg-empty"    ""   "$(gci_review_glyph '')"
check "rg-merged"   "🔀" "$(gci_review_glyph merged)"

# gci_mr_section — My-MRs pane bucketing
check "sec-approved" "ready"  "$(gci_mr_section approved)"
check "sec-conflict" "action" "$(gci_mr_section conflict)"
check "sec-changes"  "action" "$(gci_mr_section changes)"
check "sec-draft"    ""       "$(gci_mr_section draft)"
check "sec-awaiting" ""       "$(gci_mr_section awaiting)"

# gci_gitlab_review_state — detailed_merge_status [+ blocking_discussions_resolved] -> canonical
check "gl-conflict"   "conflict" "$(gci_gitlab_review_state conflict)"
check "gl-discuss"    "changes"  "$(gci_gitlab_review_state discussions_not_resolved)"
check "gl-draft"      "draft"    "$(gci_gitlab_review_state draft_status)"
check "gl-mergeable"  "approved" "$(gci_gitlab_review_state mergeable)"
check "gl-notapprv"   "awaiting" "$(gci_gitlab_review_state not_approved)"
check "gl-cimust"     "awaiting" "$(gci_gitlab_review_state ci_must_pass)"
check "gl-unblocked"  "changes"  "$(gci_gitlab_review_state ci_still_running false)"
check "gl-blocked-ok" "awaiting" "$(gci_gitlab_review_state ci_still_running true)"

# gci_gitlab_blocking_resolved — MR JSON -> "true"/"false"; a real false must survive
# (jq's `//` treats false as falsy and would erase it), missing/null still defaults true.
check "blk-false"   "false" "$(gci_gitlab_blocking_resolved '{"blocking_discussions_resolved":false}')"
check "blk-true"    "true"  "$(gci_gitlab_blocking_resolved '{"blocking_discussions_resolved":true}')"
check "blk-missing" "true"  "$(gci_gitlab_blocking_resolved '{"detailed_merge_status":"mergeable"}')"
check "blk-null"    "true"  "$(gci_gitlab_blocking_resolved '{"blocking_discussions_resolved":null}')"

# gci_github_review_state — (isDraft, mergeable, reviewDecision, unresolved) -> canonical
check "gh-conflict"      "conflict" "$(gci_github_review_state false CONFLICTING APPROVED 0)"
check "gh-changes-dec"   "changes"  "$(gci_github_review_state false MERGEABLE CHANGES_REQUESTED 0)"
check "gh-changes-thr"   "changes"  "$(gci_github_review_state false MERGEABLE REVIEW_REQUIRED 2)"
check "gh-draft"         "draft"    "$(gci_github_review_state true MERGEABLE REVIEW_REQUIRED 0)"
check "gh-approved"      "approved" "$(gci_github_review_state false MERGEABLE APPROVED 0)"
check "gh-awaiting"      "awaiting" "$(gci_github_review_state false MERGEABLE REVIEW_REQUIRED 0)"
check "gh-unknown"       "awaiting" "$(gci_github_review_state false UNKNOWN '' 0)"
check "gh-conflict-wins" "conflict" "$(gci_github_review_state true CONFLICTING CHANGES_REQUESTED 3)"
# Re-requested review: pending request neutralizes the sticky reviewDecision and unresolved
# threads (both outlive a re-request), but never a standing CHANGES_REQUESTED review.
check "gh-rerequest"     "awaiting" "$(gci_github_review_state false MERGEABLE CHANGES_REQUESTED 2 0 1)"
check "gh-rereq-thr"     "awaiting" "$(gci_github_review_state false MERGEABLE REVIEW_REQUIRED 2 0 1)"
check "gh-standing-wins" "changes"  "$(gci_github_review_state false MERGEABLE CHANGES_REQUESTED 0 1 1)"
check "gh-first-request" "awaiting" "$(gci_github_review_state false MERGEABLE REVIEW_REQUIRED 0 0 1)"
# A pending request must never demote approved or draft, and a standing changes-request
# must still beat draft (changes > draft precedence).
check "gh-approved-pend"  "approved" "$(gci_github_review_state false MERGEABLE APPROVED 0 0 1)"
check "gh-draft-pend"     "draft"    "$(gci_github_review_state true MERGEABLE CHANGES_REQUESTED 2 0 1)"
check "gh-standing-draft" "changes"  "$(gci_github_review_state true MERGEABLE CHANGES_REQUESTED 0 1 0)"

# gci_review_for_mr end to end against a canned GraphQL response: a gh() function shadows
# the binary inside the command substitution. Pins the jq parse layer — isDraft:false must
# not early-return (jq `//` treats false as falsy) — and the six-argument call order.
gh() { printf '%s' "$GH_FIXTURE"; }
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":false}]},"reviewRequests":{"totalCount":1},"latestOpinionatedReviews":{"nodes":[]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rerequest" "awaiting" "$GCI_REVIEW"
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED"}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-standing" "changes" "$GCI_REVIEW"

# Re-request regression. GitHub does NOT drop a re-requested reviewer from
# latestOpinionatedReviews — verified live on PR Photoroom/content_backend#3397, where
# `marekzp` sat in latestOpinionatedReviews as CHANGES_REQUESTED *and* in reviewRequests
# at the same time. Counting every standing verdict pinned such a PR to `changes` forever
# and hid the re-request; a standing verdict counts only while its author is not pending.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":2,"nodes":[{"requestedReviewer":{"login":"pr-machine-user"}},{"requestedReviewer":{"login":"marekzp"}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-same-author" "awaiting" "$GCI_REVIEW"
# Control: a DIFFERENT reviewer is pending, so marekzp's verdict still stands.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1,"nodes":[{"requestedReviewer":{"login":"someone-else"}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-other-author" "changes" "$GCI_REVIEW"
# A team review request has no login; it must not accidentally retire a user's verdict.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1,"nodes":[{"requestedReviewer":{}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-team" "changes" "$GCI_REVIEW"
# GCI_REQUIRED_NAMES extraction from the same PR projection (no extra API call).
ROLLUP='"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"CheckRun","name":"lint / pre_commit","isRequired":false},
  {"__typename":"CheckRun","name":"migrations-checks","isRequired":true}]}}}}]}'
PR_HEAD='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":0,"nodes":[]},"latestOpinionatedReviews":{"nodes":[]},'
GH_FIXTURE="$PR_HEAD$ROLLUP}}}}"
gci_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-only-required" "$(printf 'django-test\nmigrations-checks')" "$GCI_REQUIRED_NAMES"

# A required legacy StatusContext disables filtering: REST commits/<sha>/check-runs returns
# check runs ONLY, so filtering by name would drop a failing required status and show green
# while the merge is blocked. Empty = fall back to counting everything.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":true}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-statuscontext-guard" "" "$GCI_REQUIRED_NAMES"
# A NON-required StatusContext is harmless — filtering still applies.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":false}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-optional-statuscontext" "django-test" "$GCI_REQUIRED_NAMES"
# No branch protection at all -> nothing required -> no filtering.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":false}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-none-required" "" "$GCI_REQUIRED_NAMES"
# An absent rollup (repo with no checks, or an older projection) must yield empty, not an error.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":0,"nodes":[]},"latestOpinionatedReviews":{"nodes":[]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-absent-rollup" "" "$GCI_REQUIRED_NAMES"
check "reqnames-absent-rollup-review" "approved" "$GCI_REVIEW"
# Loop-carried-state guard: the names must NOT survive into the next space's lookup. A repo
# with no PR (path/iid empty) returns early — it must still have cleared the previous set,
# or two worktrees of one repo would filter each other's CI by a sibling PR's guards.
GH_FIXTURE="$PR_HEAD$ROLLUP}}}}"
gci_review_for_mr "$DIR" myorg/app 1 github            # populates the names
gci_review_for_mr "$DIR" "" "" github                  # no PR: must reset
check "reqnames-not-loop-carried" "" "$GCI_REQUIRED_NAMES"
# GCI_REQUIRED_OPAQUE distinguishes "nothing is required" (hide the CI cell) from "guards
# exist but cannot be filtered by name" (show the unfiltered verdict). Both leave
# GCI_REQUIRED_NAMES empty, so the cell rule needs the second signal.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":true}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "opaque-set-on-statuscontext" "1" "$GCI_REQUIRED_OPAQUE"
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":false}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
check "opaque-unset-when-none-required" "" "$GCI_REQUIRED_OPAQUE"
GH_FIXTURE="$PR_HEAD$ROLLUP}}}}"
gci_review_for_mr "$DIR" myorg/app 1 github
check "opaque-unset-when-filterable" "" "$GCI_REQUIRED_OPAQUE"
# Resets like GCI_REQUIRED_NAMES, or a no-PR space would inherit it and show a cell.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":true}]}}}}]}}}}}'
gci_review_for_mr "$DIR" myorg/app 1 github
gci_review_for_mr "$DIR" "" "" github
check "opaque-not-loop-carried" "" "$GCI_REQUIRED_OPAQUE"

unset -f gh

# gci_strip_ci_prefix with a review glyph on the MR token (review-state badge)
check "strip-rev-ready"    "inventory"   "$(gci_strip_ci_prefix '🟢 ✅!250 inventory')"
check "strip-rev-changes"  "billing-api" "$(gci_strip_ci_prefix '🔴 💬!88 billing-api')"
check "strip-rev-conflict" "payments"    "$(gci_strip_ci_prefix '🔴 ⚠️!300 payments')"
check "strip-rev-pr"       "web-app"     "$(gci_strip_ci_prefix '🟢 ✅#41 web-app')"
check "strip-rev-noemoji"  "svc"         "$(gci_strip_ci_prefix '✅!7 svc')"
# A user label that merely starts with one of the glyphs (no MR sigil) is preserved:
check "strip-rev-keep"     "✅ done"      "$(gci_strip_ci_prefix '✅ done')"
# Idempotent: re-stripping an already-clean label is a no-op:
check "strip-rev-idem"     "inventory"   "$(gci_strip_ci_prefix "$(gci_strip_ci_prefix '🟢 ✅!250 inventory')")"

# gci_strip_ci_prefix with the 🔀 merged-PR/MR token (positive merged badge)
check "strip-merged-pr"    "dbt"         "$(gci_strip_ci_prefix '🔀#123 dbt')"
check "strip-merged-mr"    "dbt"         "$(gci_strip_ci_prefix '🔀!123 dbt')"
check "strip-merged-full"  "web-app"     "$(gci_strip_ci_prefix '🟢 🔀#42 web-app')"
check "strip-merged-idem"  "dbt"         "$(gci_strip_ci_prefix "$(gci_strip_ci_prefix '🟢 🔀#123 dbt')")"

# gci_pane_cwds — ordered cwds of a workspace's panes (pure; foreground_cwd, else cwd).
panes_ord='{"result":{"panes":[
  {"workspace_id":"wA","foreground_cwd":"/a","cwd":"/A"},
  {"workspace_id":"wA","cwd":"/b"},
  {"workspace_id":"wX","cwd":"/x"}
]}}'
check "pane-cwds-order" "/a,/b" "$(gci_pane_cwds wA "$panes_ord" | paste -sd, -)"
check "pane-cwds-other" "/x"    "$(gci_pane_cwds wX "$panes_ord")"
check "pane-cwds-none"  ""      "$(gci_pane_cwds wZ "$panes_ord")"

# gci_git_has_origin — true only for a git work tree that has an origin remote.
ght="$(mktemp -d)"
git -C "$ght" init -q                                             # git, no origin
gci_git_has_origin "$ght";      check "origin-none"    "1" "$?"
git -C "$ght" remote add origin git@gitlab.com:me/proj.git
gci_git_has_origin "$ght";      check "origin-yes"     "0" "$?"   # git + origin
gci_git_has_origin "$ght/nope"; check "origin-nonrepo" "1" "$?"
gci_git_has_origin "";          check "origin-empty"   "1" "$?"
rm -rf "$ght"

# gci_pick_pane_cwd — prefer the first pane that is a git repo WITH an origin remote, so a
# remote-less git dir (e.g. the status-bar plugin's own repo) never shadows the real repo.
pt="$(mktemp -d)"; mkdir -p "$pt/plug" "$pt/repo" "$pt/plain"
git -C "$pt/plug" init -q                                         # git, NO origin (like the bar)
git -C "$pt/repo" init -q; git -C "$pt/repo" remote add origin git@github.com:me/app.git
pick_json='{"result":{"panes":[
  {"workspace_id":"wA","label":"status-bar","foreground_cwd":"'"$pt/plug"'"},
  {"workspace_id":"wA","cwd":"'"$pt/plain"'"},
  {"workspace_id":"wA","foreground_cwd":"'"$pt/repo"'"}
]}}'
# The status-bar (remote-less git) and non-git panes are skipped; the repo-with-origin wins:
check "cwd-git-remote"   "$pt/repo" "$(gci_pick_pane_cwd wA "$pick_json")"
# No pane has a remote -> fall back to the first pane's cwd:
pick_none='{"panes":[{"workspace_id":"wB","cwd":"'"$pt/plug"'"},{"workspace_id":"wB","cwd":"'"$pt/plain"'"}]}'
check "cwd-git-fallback" "$pt/plug" "$(gci_pick_pane_cwd wB "$pick_none")"
# Unknown workspace -> empty:
check "cwd-git-none"     ""         "$(gci_pick_pane_cwd wZ "$pick_json")"
# An installed plugin's own checkout (cwd under the herdr plugins root) HAS an origin remote,
# so the origin heuristic alone can't reject it — it must be skipped by path, and must never
# shadow the real repo pane nor serve as the fallback:
mkdir -p "$pt/plugins/github"
git -C "$pt/plugins/github" init -q
git -C "$pt/plugins/github" remote add origin https://github.com/x/some-plugin.git
pick_plug='{"result":{"panes":[
  {"workspace_id":"wC","foreground_cwd":"'"$pt/plugins/github"'"},
  {"workspace_id":"wC","foreground_cwd":"'"$pt/repo"'"}
]}}'
check "cwd-skip-plugin" "$pt/repo" "$(GCI_PLUGINS_ROOT="$pt/plugins" gci_pick_pane_cwd wC "$pick_plug")"
pick_plug_only='{"panes":[
  {"workspace_id":"wD","cwd":"'"$pt/plugins/github"'"},
  {"workspace_id":"wD","cwd":"'"$pt/plain"'"}
]}'
check "cwd-plugin-fallback" "$pt/plain" "$(GCI_PLUGINS_ROOT="$pt/plugins" gci_pick_pane_cwd wD "$pick_plug_only")"
rm -rf "$pt"

# gci_upstream_path — fork checkouts: `upstream` remote on the SAME host as origin -> its
# slug (used to retry PR/MR + CI lookups in the base repo); anything else -> empty.
ut="$(mktemp -d)"
git -C "$ut" init -q
check "up-no-origin"   ""         "$(gci_upstream_path "$ut")"
git -C "$ut" remote add origin git@github.com:me/app.git
check "up-no-upstream" ""         "$(gci_upstream_path "$ut")"
git -C "$ut" remote add upstream git@github.com:core/app.git
check "up-same-host"   "core/app" "$(gci_upstream_path "$ut")"
git -C "$ut" remote set-url upstream https://github.com/core/app
check "up-https-form"  "core/app" "$(gci_upstream_path "$ut")"
git -C "$ut" remote set-url upstream git@gitlab.com:core/app.git
check "up-other-host"  ""         "$(gci_upstream_path "$ut")"
check "up-nonrepo"     ""         "$(gci_upstream_path "$ut/nope")"
rm -rf "$ut"

# gci_daemon_alive — true only when <pidfile> exists and names a live process. Backs the
# poller's is_running check and its self-healing `start` (which relaunches when this is false).
dtmp="$(mktemp)"
echo $$ > "$dtmp"                                   # our own pid -> alive
gci_daemon_alive "$dtmp"; check "daemon-alive-self" "0" "$?"
( exit 0 ) & deadpid=$!; wait "$deadpid" 2>/dev/null # a reaped child -> dead
echo "$deadpid" > "$dtmp"
gci_daemon_alive "$dtmp"; check "daemon-dead-pid"  "1" "$?"
: > "$dtmp"                                          # empty pidfile -> not alive
gci_daemon_alive "$dtmp"; check "daemon-empty"     "1" "$?"
rm -f "$dtmp"                                        # missing pidfile -> not alive
gci_daemon_alive "$dtmp"; check "daemon-nofile"    "1" "$?"

# gci_pid_matches — identity, not just liveness (pid reuse after reboot)
gci_pid_matches $$ "test.sh";           check "pidmatch-self"     "0" "$?"
gci_pid_matches $$ "poller-ctl.sh run"; check "pidmatch-mismatch" "1" "$?"
bash -c 'exit 0' & _dead=$!; wait "$_dead" 2>/dev/null
gci_pid_matches "$_dead" "test.sh";     check "pidmatch-deadpid"  "1" "$?"

# gci_daemon_alive with pattern arg
echo $$ > "$dtmp"
gci_daemon_alive "$dtmp" "test.sh";           check "daemon-alive-pattern"    "0" "$?"
gci_daemon_alive "$dtmp" "poller-ctl.sh run"; check "daemon-reused-pid"       "1" "$?"

# gci_github_checks_status — aggregate a head commit's check runs; the highest-severity
# run decides the overall status (a repo can have many workflows per push, so sampling a
# single run — e.g. a skipped "Claude Code" workflow — misreports CI that is green/running).
# Input lines: status \t conclusion \t id \t url \t updated. Output: winner as canonical \t id \t url \t updated.
check "chk-running-wins" "running	3	u3	t3" "$(printf 'completed\tskipped\t1\tu1\tt1\ncompleted\tsuccess\t2\tu2\tt2\nin_progress\t\t3\tu3\tt3\n' | gci_github_checks_status)"
check "chk-failed-wins"  "failed	2	u2	t2"  "$(printf 'in_progress\t\t1\tu1\tt1\ncompleted\tfailure\t2\tu2\tt2\ncompleted\tsuccess\t3\tu3\tt3\n' | gci_github_checks_status)"
check "chk-success"      "success	2	u2	t2" "$(printf 'completed\tskipped\t1\tu1\tt1\ncompleted\tsuccess\t2\tu2\tt2\n' | gci_github_checks_status)"
check "chk-queued"       "pending	1	u1	t1" "$(printf 'queued\t\t1\tu1\tt1\ncompleted\tskipped\t2\tu2\tt2\n' | gci_github_checks_status)"
check "chk-skipped-only" "skipped	1	u1	t1" "$(printf 'completed\tskipped\t1\tu1\tt1\n' | gci_github_checks_status)"
check "chk-empty"        "" "$(printf '' | gci_github_checks_status)"

# gci_required_status — only merge-guarding checks decide the CI cell. Modelled on
# Photoroom/content_backend#3397, where "lint / pre_commit" failed while all three required
# checks passed, turning the whole space red for something that could not block the merge.
CR_JSON='{"check_runs":[
  {"name":"django-test","status":"completed","conclusion":"success","id":1,"html_url":"u1","completed_at":"t1"},
  {"name":"lint / pre_commit","status":"completed","conclusion":"failure","id":2,"html_url":"u2","completed_at":"t2"},
  {"name":"fastapi-test","status":"completed","conclusion":"skipped","id":3,"html_url":"u3","completed_at":"t3"},
  {"name":"migrations-checks","status":"completed","conclusion":"success","id":4,"html_url":"u4","completed_at":"t4"}]}'
REQ_3="$(printf 'django-test\nfastapi-test\nmigrations-checks')"
# Unfiltered, the failing optional lint wins:
check "req-unfiltered" "failed" "$(printf '%s' "$CR_JSON" \
  | jq -r '.check_runs[]|[.status,.conclusion//"",(.id|tostring),.html_url//"",(.completed_at//"")]|@tsv' \
  | gci_github_checks_status | cut -f1)"
# Filtered to the merge guards, it does not — and a SKIPPED required check does not veto,
# matching GitHub's merge box:
check "req-filtered"   "success" "$(gci_required_status "$CR_JSON" "$REQ_3" | cut -f1)"
# A required check that IS failing still wins:
check "req-fail-wins"  "failed"  "$(gci_required_status "$CR_JSON" "$(printf 'django-test\nlint / pre_commit')" | cut -f1)"
# Empty name list = "do not filter": prints nothing, caller keeps the unfiltered verdict.
check "req-no-names"   ""        "$(gci_required_status "$CR_JSON" "")"
# None of the required checks has run on this commit yet: also nothing, so the caller falls
# back rather than reporting the branch as having no CI.
check "req-absent"     ""        "$(gci_required_status "$CR_JSON" "not-run-here")"
# A name is matched whole, not as a substring — "test" must not match "django-test".
check "req-exact-name" ""        "$(gci_required_status "$CR_JSON" "test")"

# gci_latest_ci (github) — a branch missing on the remote (deleted on merge, or not pushed
# yet) makes commits/<ref>/check-runs fail with HTTP 422 "No commit found for SHA". That is
# "no CI" (rc 0, empty status), NOT a transient api-error (rc 5): rc 5 makes the poller SKIP
# the workspace forever, freezing a stale label and never applying the merged badge.
lct="$(mktemp -d)"
git -C "$lct" init -q
git -C "$lct" remote add origin git@github.com:acme/web-app.git
git -C "$lct" -c user.email=t@t -c user.name=t commit --allow-empty -q -m x
gh() { printf 'gh: No commit found for SHA: gone-branch (HTTP 422)'; return 1; }
gci_latest_ci "$lct"
check "ci-deleted-branch-rc"     "0" "$?"
check "ci-deleted-branch-status" ""  "$GCI_STATUS"
unset -f gh; rm -rf "$lct"

# gci_review_for_mr (github) — isDraft:false must survive extraction (jq `//` treats false
# as falsy, so `// empty` would erase it and no non-draft PR could ever get a review state).
gh() { printf '%s' "$GH_STUB"; } # shadows the gh CLI inside gci_review_for_mr
GH_STUB='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]}}}}}'
gci_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-nondraft" "approved" "$GCI_REVIEW"
GH_STUB='{"data":{"repository":{"pullRequest":{"isDraft":true,"mergeable":"MERGEABLE","reviewDecision":null,"reviewThreads":{"nodes":[]}}}}}'
gci_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-draft"    "draft"    "$GCI_REVIEW"
GH_STUB='{"data":{"repository":{"pullRequest":null}}}'
gci_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-missing"  ""         "$GCI_REVIEW"
unset -f gh

# Configurable icons — GITLAB_CI_ICON_* overrides (defaults are pinned by the em-*/rg-*/rb-*
# checks above, which run with all icon vars unset).
check "ov-ok"         "X" "$(GITLAB_CI_ICON_OK=X gci_status_emoji success)"
check "ov-fail"       "F" "$(GITLAB_CI_ICON_FAIL=F gci_status_emoji failed)"
check "ov-run"        "R" "$(GITLAB_CI_ICON_RUN=R gci_status_emoji pending)"
check "ov-none"       "N" "$(GITLAB_CI_ICON_NONE=N gci_status_emoji canceled)"
check "ov-approved"   "A" "$(GITLAB_CI_ICON_APPROVED=A gci_review_glyph approved)"
check "ov-draft"      "D" "$(GITLAB_CI_ICON_DRAFT=D gci_review_glyph draft)"
check "ov-conflict"   "C" "$(GITLAB_CI_ICON_CONFLICT=C gci_review_glyph conflict)"
# Set-but-EMPTY hides the glyph (e.g. no dot for "no pipeline"):
check "ov-none-empty" ""  "$(GITLAB_CI_ICON_NONE= gci_status_emoji canceled)"

# Strip round-trip with overrides: label built the way poll_once builds it.
# The token is built the way status_for_repo builds it: "<badge> <sigil><id>" (space between
# the review badge and the id, per the space-before-pr-id change). strip must handle the space
# or the whole "<badge> #12" token accumulates on every poll.
check "ov-strip-roundtrip" "dbt" "$(
  GITLAB_CI_ICON_OK=✔ GITLAB_CI_ICON_APPROVED=A
  gci_strip_ci_prefix "$(gci_status_emoji success) $(gci_review_glyph approved) !12 dbt"
)"
# Same, GitHub sigil + a default (non-override) badge glyph, and idempotent on a doubled token:
check "ov-strip-badge-spaced"  "dbt" "$(gci_strip_ci_prefix "$(gci_review_glyph approved) #12 dbt")"
check "ov-strip-badge-glued"   "dbt" "$(gci_strip_ci_prefix "$(gci_review_glyph approved)#12 dbt")"
# The default emoji must STILL strip while overrides are active, or labels decorated
# before an icon-config change accumulate prefixes on the first poll after it:
check "ov-strip-default"   "dbt" "$(GITLAB_CI_ICON_OK=✔ gci_strip_ci_prefix '🟢 dbt')"
# Empty round-trip: no dot emitted, MR token still stripped:
check "ov-empty-roundtrip" "svc" "$(GITLAB_CI_ICON_NONE= gci_strip_ci_prefix "$(gci_status_emoji unknown)!123 svc")"
# Empty-override guard: an empty pattern must be skipped by strip ("" matches anything —
# here it would eat the leading space of the label):
check "ov-empty-strip"     " x"  "$(GITLAB_CI_ICON_NONE= gci_strip_ci_prefix ' x')"

# gci_ttl_ms — the TTL must outlast the republish period (cycle + sleep), so it is derived
# from the MEASURED cycle, not from the interval alone. Floor covers the first pass.
check "ttl-floor"      "90000"  "$(gci_ttl_ms 0 30)"     # 3*(0+30)=90s -> floor
check "ttl-floor-fast" "90000"  "$(gci_ttl_ms 0 1)"      # 3*(0+1)=3s -> floor wins
check "ttl-measured"   "225000" "$(gci_ttl_ms 45 30)"    # 3*(45+30)=225s, the live cycle
check "ttl-grows"      "450000" "$(gci_ttl_ms 120 30)"   # a slower cycle stretches the TTL

# gci_status_bucket — the token NAME carries the state, because herdr's token style is
# static config: one token cannot change colour per state.
check "bucket-ok"      "ok"   "$(gci_status_bucket success)"
check "bucket-fail"    "fail" "$(gci_status_bucket failed)"
check "bucket-run"     "run"  "$(gci_status_bucket pending)"
check "bucket-run-sch" "run"  "$(gci_status_bucket scheduled)"
check "bucket-none"    "none" "$(gci_status_bucket canceled)"
check "bucket-empty"   "none" "$(gci_status_bucket '')"

# gci_ci_cell — labelled cell, but a glyph hidden by a set-but-empty override stays
# fully hidden instead of rendering a bare "CI".
check "cell-ok"      "CI 🟢" "$(gci_ci_cell success)"
check "cell-fail"    "CI 🔴" "$(gci_ci_cell failed)"
check "cell-ov"      "CI X"  "$(GITLAB_CI_ICON_OK=X gci_ci_cell success)"
check "cell-hidden"  ""      "$(GITLAB_CI_ICON_NONE= gci_ci_cell canceled)"

# gci_review_cell — labelled like the CI cell; a hidden glyph stays fully hidden.
check "rcell-approved" "R ✅" "$(gci_review_cell approved)"
check "rcell-changes"  "R 💬" "$(gci_review_cell changes)"
check "rcell-merged"   "R 🔀" "$(gci_review_cell merged)"
check "rcell-ov"       "R A"  "$(GITLAB_CI_ICON_APPROVED=A gci_review_cell approved)"
check "rcell-hidden"   ""     "$(GITLAB_CI_ICON_AWAITING= gci_review_cell awaiting)"
check "rcell-none"     ""     "$(gci_review_cell '')"

# Token names: one prefix moves every token out of a colliding plugin's way.
check "tok-default"  "ci_ok"     "$(gci_token_name ci_ok)"
check "tok-prefixed" "gci_ci_ok" "$(GITLAB_CI_TOKEN_PREFIX=gci_ gci_token_name ci_ok)"

ttmp="$(mktemp -d)"
cat > "$ttmp/herdr" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TLOG"
case "$1.$2" in
  workspace.list) echo '{"result":{"workspaces":[{"workspace_id":"wT","label":"🟢 #12 proj"}]}}' ;;
  pane.list)      echo '{"result":{"panes":[]}}' ;;
esac
exit 0
STUB
chmod +x "$ttmp/herdr"

# gci_report_tokens — CI and review each publish under the token named for their current
# state and send every sibling state EMPTY (which clears it), so exactly one of each is
# live per space and the user's per-state fg can colour it. All in ONE call: --seq is per
# (workspace, source), so a second call in the same second would be dropped.
: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" \
  gci_report_tokens wX pending changes "#7" 42 9000
check "report-one-call" "1" "$(wc -l < "$ttmp/log" | tr -d ' ')"
grep -q -- '--token ci_run=CI 🟡' "$ttmp/log";        check "report-ci-live-state"    "0" "$?"
grep -q -- '--token ci_ok= --token ci_fail= ' "$ttmp/log"; check "report-ci-siblings-cleared" "0" "$?"
grep -q -- '--token review_changes=R 💬' "$ttmp/log"; check "report-review-live-state" "0" "$?"
grep -q -- '--token review_approved= ' "$ttmp/log";   check "report-review-siblings-cleared" "0" "$?"
grep -q -- '--token mr=#7 --seq 42 --ttl-ms 9000' "$ttmp/log"; check "report-tail" "0" "$?"
# No CI and no PR at all: every token empty, nothing stale left behind.
: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" gci_report_tokens wX "" "" "" 44 9000
grep -q -- '--token ci_none= --token review_conflict=' "$ttmp/log"
check "report-empty-state-clears-all" "0" "$?"

: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" gci_clear_tokens wX 43
for _t in ci_ok ci_fail ci_run ci_none review_conflict review_changes review_draft \
          review_approved review_awaiting review_merged mr; do
  grep -q -- "--clear-token $_t" "$ttmp/log" || { check "clear-covers-$_t" "0" "1"; }
done
check "clear-covers-every-token" "11" "$(grep -o -- '--clear-token' "$ttmp/log" | wc -l | tr -d ' ')"

# poll-once publishes tokens and NEVER renames — the whole point of the migration. The
# fake workspace carries a label decorated by a pre-token version ("🟢 #12 proj"); the old
# code would strip and re-apply it, the token version must leave the label alone.
tctl() { env HERDR_PLUGIN_STATE_DIR="$ttmp/state" HERDR_PLUGIN_CONFIG_DIR="$ttmp" \
             HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" GITLAB_CI_REFRESH=1 \
             bash "$DIR/poller-ctl.sh" "$@"; }

: > "$ttmp/log"; tctl poll-once >/dev/null 2>&1
grep -q -- 'report-metadata wT --source gitlab-ci-status --token ci_ok= --token ci_fail= --token ci_run= --token ci_none= --token review_conflict= --token review_changes= --token review_draft= --token review_approved= --token review_awaiting= --token review_merged= --token mr= --seq' "$ttmp/log"
check "poll-reports-all-tokens" "0" "$?"
check "poll-single-report" "1" "$(grep -c 'report-metadata' "$ttmp/log")"
grep -q -- '--ttl-ms 90000' "$ttmp/log"
check "poll-ttl-floor-applied" "0" "$?"
grep -q 'workspace rename' "$ttmp/log"
check "poll-never-renames" "1" "$?"

: > "$ttmp/log"; GITLAB_CI_TOKEN_PREFIX=x_ tctl poll-once >/dev/null 2>&1
grep -q -- '--token x_ci_ok= .* --token x_review_changes= .* --token x_mr=' "$ttmp/log"
check "poll-honors-token-prefix" "0" "$?"

# restore — the migration path: clear our tokens AND strip the stale label decoration.
: > "$ttmp/log"; tctl restore >/dev/null 2>&1
grep -q -- 'report-metadata wT --source gitlab-ci-status --clear-token ci_ok' "$ttmp/log"
check "restore-clears-tokens" "0" "$?"
grep -q 'workspace rename wT proj' "$ttmp/log"
check "restore-strips-label"  "0" "$?"
rm -rf "$ttmp"

# poller-ctl ensure — restart after unexpected death only
etmp="$(mktemp -d)"
printf '#!/bin/sh\necho "{\\"result\\":{\\"workspaces\\":[]}}"\n' > "$etmp/herdr"
chmod +x "$etmp/herdr"
pctl() { env HERDR_PLUGIN_STATE_DIR="$etmp/state" HERDR_PLUGIN_CONFIG_DIR="$etmp" \
             HERDR_BIN_PATH="$etmp/herdr" GITLAB_CI_REFRESH=1 GITLAB_CI_START_HEAL_SECS=0 \
             bash "$DIR/poller-ctl.sh" "$@"; }

pctl ensure >/dev/null 2>&1
[ -f "$etmp/state/poller.pid" ]; check "ensure-no-pidfile-stays-stopped" "1" "$?"

bash -c 'exit 0' & _dead=$!; wait "$_dead" 2>/dev/null
mkdir -p "$etmp/state"; echo "$_dead" > "$etmp/state/poller.pid"
pctl ensure >/dev/null 2>&1
gci_daemon_alive "$etmp/state/poller.pid" "poller-ctl.sh run"; check "ensure-restarts-dead" "0" "$?"

_before="$(cat "$etmp/state/poller.pid")"
pctl ensure >/dev/null 2>&1
check "ensure-noop-when-running" "$_before" "$(cat "$etmp/state/poller.pid")"

pctl stop >/dev/null 2>&1
[ -f "$etmp/state/poller.pid" ]; check "stop-removes-pidfile" "1" "$?"
pctl ensure >/dev/null 2>&1
[ -f "$etmp/state/poller.pid" ]; check "ensure-respects-stop" "1" "$?"

# ensure-over-foreign-pid: restart daemon over a reused (foreign) pid, never signal it
sleep 100 & _foreign=$!
echo "$_foreign" > "$etmp/state/poller.pid"
pctl ensure >/dev/null 2>&1
gci_daemon_alive "$etmp/state/poller.pid" "poller-ctl.sh run"; check "ensure-over-foreign-pid-restarted" "0" "$?"
kill -0 "$_foreign" 2>/dev/null; check "ensure-over-foreign-pid-untouched" "0" "$?"
pctl stop >/dev/null 2>&1

# stop-ignores-foreign-pid: stop never signals a reused pid, identity guard protects it
echo "$_foreign" > "$etmp/state/poller.pid"
pctl stop >/dev/null 2>&1
[ -f "$etmp/state/poller.pid" ]; check "stop-ignores-foreign-removes-pidfile" "1" "$?"
kill -0 "$_foreign" 2>/dev/null; check "stop-ignores-foreign-alive" "0" "$?"
kill "$_foreign" 2>/dev/null

rm -rf "$etmp"

exit $fail
