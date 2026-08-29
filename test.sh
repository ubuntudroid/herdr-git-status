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

# gst_parse_remote — all URL shapes -> "host<TAB>path"
check "ssh-scp"     "gitlab.com	myteam/my-service" "$(gst_parse_remote 'git@gitlab.com:myteam/my-service.git')"
check "ssh-url"     "gitlab.com	myteam/my-service" "$(gst_parse_remote 'ssh://git@gitlab.com/myteam/my-service.git')"
check "https"       "gitlab.com	myteam/my-service" "$(gst_parse_remote 'https://gitlab.com/myteam/my-service.git')"
check "https-token" "gitlab.com	myteam/my-service" "$(gst_parse_remote 'https://oauth2:tok@gitlab.com/myteam/my-service.git')"
check "subgroup"    "gitlab.com	grp/sub/proj"      "$(gst_parse_remote 'git@gitlab.com:grp/sub/proj.git')"
check "no-suffix"   "gitlab.com	myteam/my-service" "$(gst_parse_remote 'https://gitlab.com/myteam/my-service')"
gst_parse_remote 'not a url' >/dev/null 2>&1; check "bad-url-returns-1" "1" "$?"

# gst_urlencode_path
check "encode"      "grp%2Fsub%2Fproj" "$(gst_urlencode_path 'grp/sub/proj')"

# gst_status_glyph (NO_COLOR -> plain text)
check "st-success"  "✓ passed"  "$(gst_status_glyph success)"
check "st-failed"   "✗ failed"  "$(gst_status_glyph failed)"
check "st-running"  "● running" "$(gst_status_glyph running)"
check "st-manual"   "⚙ manual"  "$(gst_status_glyph manual)"
check "st-unknown"  "weird"     "$(gst_status_glyph weird)"

# gst_relative_time with fixed now (ref = 2026-06-25T08:30:00 + 120s)
ref_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' '2026-06-25T08:32:00' +%s 2>/dev/null || date -u -d '2026-06-25T08:32:00' +%s)"
check "rel-2m"      "2m ago"    "$(gst_relative_time '2026-06-25T08:30:00.000Z' "$ref_epoch")"

# gst_status_emoji
check "em-success"  "🟢" "$(gst_status_emoji success)"
check "em-failed"   "🔴" "$(gst_status_emoji failed)"
check "em-running"  "🟡" "$(gst_status_emoji running)"
check "em-pending"  "🟡" "$(gst_status_emoji pending)"
check "em-other"    "⚪" "$(gst_status_emoji canceled)"

# gst_strip_ci_prefix (idempotent label cleanup)
check "strip-green"   "dbt"               "$(gst_strip_ci_prefix '🟢 dbt')"
check "strip-red"     "GQL review"        "$(gst_strip_ci_prefix '🔴 GQL review')"
check "strip-white"   "bakku-daemon"      "$(gst_strip_ci_prefix '⚪ bakku-daemon')"
check "strip-none"    "herdr"             "$(gst_strip_ci_prefix 'herdr')"
check "strip-nospace" "x"                 "$(gst_strip_ci_prefix '🟡x')"
check "strip-emoji-in-name" "my 🟢 repo"  "$(gst_strip_ci_prefix 'my 🟢 repo')"

# gst_strip_ci_prefix with the !<iid> merge-request token
check "strip-emoji-mr"   "dbt"          "$(gst_strip_ci_prefix '🟢 !123 dbt')"
check "strip-emoji-mr2"  "GQL review"   "$(gst_strip_ci_prefix '🔴 !7 GQL review')"
check "strip-mr-only"    "standalone"   "$(gst_strip_ci_prefix '!42 standalone')"
check "strip-mr-notnum"  "!abc foo"     "$(gst_strip_ci_prefix '!abc foo')"
check "strip-mr-bang"    "!important"   "$(gst_strip_ci_prefix '!important')"

# gst_hyperlink — NO_COLOR/non-tty falls back to plain text (no escape sequences)
check "hyperlink-plain"  "!123"         "$(gst_hyperlink 'https://gitlab.com/x/-/merge_requests/123' '!123')"

# gst_provider — host -> provider
check "prov-gitlab"  "gitlab" "$(gst_provider gitlab.com)"
check "prov-github"  "github" "$(gst_provider github.com)"
check "prov-gh-ent"  "github" "$(gst_provider github.acme.com)"
check "prov-self-gl" "gitlab" "$(gst_provider gitlab.example.org)"
check "prov-none"    ""       "$(gst_provider bitbucket.org)"

# gst_github_status — (status, conclusion) -> canonical status
check "gh-success"   "success"  "$(gst_github_status completed success)"
check "gh-failure"   "failed"   "$(gst_github_status completed failure)"
check "gh-timeout"   "failed"   "$(gst_github_status completed timed_out)"
check "gh-running"   "running"  "$(gst_github_status in_progress '')"
check "gh-queued"    "pending"  "$(gst_github_status queued '')"
check "gh-cancelled" "canceled" "$(gst_github_status completed cancelled)"
check "gh-skipped"   "skipped"  "$(gst_github_status completed skipped)"
check "gh-neutral"   "manual"   "$(gst_github_status completed neutral)"

# gst_strip_ci_prefix with the #<num> PR token (GitHub)
check "strip-emoji-pr"  "web app"  "$(gst_strip_ci_prefix '🟢 #42 web app')"
check "strip-pr-only"   "api"      "$(gst_strip_ci_prefix '#7 api')"
check "strip-pr-notnum" "#tag x"   "$(gst_strip_ci_prefix '#tag x')"

# gst_pane_title — provider-aware herdr pane label, derived from origin (no API call)
ptdir="$(mktemp -d)"
git -C "$ptdir" init -q 2>/dev/null
git -C "$ptdir" remote add origin 'git@github.com:acme/web-app.git' 2>/dev/null
check "title-github" "GitHub CI" "$(gst_pane_title "$ptdir")"
git -C "$ptdir" remote set-url origin 'https://gitlab.com/myteam/dbt.git' 2>/dev/null
check "title-gitlab" "GitLab CI" "$(gst_pane_title "$ptdir")"
git -C "$ptdir" remote set-url origin 'https://bitbucket.org/x/y.git' 2>/dev/null
check "title-other"  "CI"        "$(gst_pane_title "$ptdir")"
check "title-norepo" "CI"        "$(gst_pane_title "$ptdir/nonexistent")"
rm -rf "$ptdir"

# gst_review_glyph — full canonical vocabulary -> emoji
check "rg-conflict" "⚠️" "$(gst_review_glyph conflict)"
check "rg-changes"  "💬" "$(gst_review_glyph changes)"
check "rg-draft"    "📝" "$(gst_review_glyph draft)"
check "rg-approved" "✅" "$(gst_review_glyph approved)"
check "rg-awaiting" "👀" "$(gst_review_glyph awaiting)"
check "rg-none"     ""   "$(gst_review_glyph none)"
check "rg-empty"    ""   "$(gst_review_glyph '')"
check "rg-merged"   "🔀" "$(gst_review_glyph merged)"

# gst_mr_section — My-PRs pane bucketing
check "sec-approved" "ready"  "$(gst_mr_section approved)"
check "sec-conflict" "action" "$(gst_mr_section conflict)"
check "sec-changes"  "action" "$(gst_mr_section changes)"
check "sec-draft"    ""       "$(gst_mr_section draft)"
check "sec-awaiting" ""       "$(gst_mr_section awaiting)"

# gst_gitlab_review_state — detailed_merge_status [+ blocking_discussions_resolved] -> canonical
check "gl-conflict"   "conflict" "$(gst_gitlab_review_state conflict)"
check "gl-discuss"    "changes"  "$(gst_gitlab_review_state discussions_not_resolved)"
check "gl-draft"      "draft"    "$(gst_gitlab_review_state draft_status)"
check "gl-mergeable"  "approved" "$(gst_gitlab_review_state mergeable)"
check "gl-notapprv"   "awaiting" "$(gst_gitlab_review_state not_approved)"
check "gl-cimust"     "awaiting" "$(gst_gitlab_review_state ci_must_pass)"
check "gl-unblocked"  "changes"  "$(gst_gitlab_review_state ci_still_running false)"
check "gl-blocked-ok" "awaiting" "$(gst_gitlab_review_state ci_still_running true)"

# gst_gitlab_blocking_resolved — MR JSON -> "true"/"false"; a real false must survive
# (jq's `//` treats false as falsy and would erase it), missing/null still defaults true.
check "blk-false"   "false" "$(gst_gitlab_blocking_resolved '{"blocking_discussions_resolved":false}')"
check "blk-true"    "true"  "$(gst_gitlab_blocking_resolved '{"blocking_discussions_resolved":true}')"
check "blk-missing" "true"  "$(gst_gitlab_blocking_resolved '{"detailed_merge_status":"mergeable"}')"
check "blk-null"    "true"  "$(gst_gitlab_blocking_resolved '{"blocking_discussions_resolved":null}')"

# gst_github_review_state — (isDraft, mergeable, reviewDecision, unresolved) -> canonical
check "gh-conflict"      "conflict" "$(gst_github_review_state false CONFLICTING APPROVED 0)"
check "gh-changes-dec"   "changes"  "$(gst_github_review_state false MERGEABLE CHANGES_REQUESTED 0)"
check "gh-changes-thr"   "changes"  "$(gst_github_review_state false MERGEABLE REVIEW_REQUIRED 2)"
check "gh-draft"         "draft"    "$(gst_github_review_state true MERGEABLE REVIEW_REQUIRED 0)"
check "gh-approved"      "approved" "$(gst_github_review_state false MERGEABLE APPROVED 0)"
check "gh-awaiting"      "awaiting" "$(gst_github_review_state false MERGEABLE REVIEW_REQUIRED 0)"
check "gh-unknown"       "awaiting" "$(gst_github_review_state false UNKNOWN '' 0)"
check "gh-conflict-wins" "conflict" "$(gst_github_review_state true CONFLICTING CHANGES_REQUESTED 3)"
# Re-requested review: pending request neutralizes the sticky reviewDecision and unresolved
# threads (both outlive a re-request), but never a standing CHANGES_REQUESTED review.
check "gh-rerequest"     "awaiting" "$(gst_github_review_state false MERGEABLE CHANGES_REQUESTED 2 0 1)"
check "gh-rereq-thr"     "awaiting" "$(gst_github_review_state false MERGEABLE REVIEW_REQUIRED 2 0 1)"
check "gh-standing-wins" "changes"  "$(gst_github_review_state false MERGEABLE CHANGES_REQUESTED 0 1 1)"
check "gh-first-request" "awaiting" "$(gst_github_review_state false MERGEABLE REVIEW_REQUIRED 0 0 1)"
# A pending request must never demote approved or draft, and a standing changes-request
# must still beat draft (changes > draft precedence).
check "gh-approved-pend"  "approved" "$(gst_github_review_state false MERGEABLE APPROVED 0 0 1)"
check "gh-draft-pend"     "draft"    "$(gst_github_review_state true MERGEABLE CHANGES_REQUESTED 2 0 1)"
check "gh-standing-draft" "changes"  "$(gst_github_review_state true MERGEABLE CHANGES_REQUESTED 0 1 0)"

# gst_review_for_mr end to end against a canned GraphQL response: a gh() function shadows
# the binary inside the command substitution. Pins the jq parse layer — isDraft:false must
# not early-return (jq `//` treats false as falsy) — and the six-argument call order.
gh() { printf '%s' "$GH_FIXTURE"; }
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":false}]},"reviewRequests":{"totalCount":1},"latestOpinionatedReviews":{"nodes":[]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rerequest" "awaiting" "$GST_REVIEW"
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED"}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-standing" "changes" "$GST_REVIEW"

# Re-request regression. GitHub does NOT drop a re-requested reviewer from
# latestOpinionatedReviews — verified live on PR Photoroom/content_backend#3397, where
# `marekzp` sat in latestOpinionatedReviews as CHANGES_REQUESTED *and* in reviewRequests
# at the same time. Counting every standing verdict pinned such a PR to `changes` forever
# and hid the re-request; a standing verdict counts only while its author is not pending.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":2,"nodes":[{"requestedReviewer":{"login":"pr-machine-user"}},{"requestedReviewer":{"login":"marekzp"}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-same-author" "awaiting" "$GST_REVIEW"
# Control: a DIFFERENT reviewer is pending, so marekzp's verdict still stands.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1,"nodes":[{"requestedReviewer":{"login":"someone-else"}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-other-author" "changes" "$GST_REVIEW"
# A team review request has no login; it must not accidentally retire a user's verdict.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":1,"nodes":[{"requestedReviewer":{}}]},"latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"login":"marekzp"}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "e2e-gh-rereq-team" "changes" "$GST_REVIEW"
# GST_REQUIRED_NAMES extraction from the same PR projection (no extra API call).
ROLLUP='"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"CheckRun","name":"lint / pre_commit","isRequired":false},
  {"__typename":"CheckRun","name":"migrations-checks","isRequired":true}]}}}}]}'
PR_HEAD='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":0,"nodes":[]},"latestOpinionatedReviews":{"nodes":[]},'
GH_FIXTURE="$PR_HEAD$ROLLUP}}}}"
gst_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-only-required" "$(printf 'django-test\nmigrations-checks')" "$GST_REQUIRED_NAMES"

# A required legacy StatusContext is keyed on .context and is included like any check run —
# the CI verdict comes from the same rollup, which carries commit statuses too.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":true}]}}}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-statuscontext-included" "$(printf 'django-test\nci/legacy')" "$GST_REQUIRED_NAMES"
# A NON-required StatusContext is harmless — filtering still applies.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":true},
  {"__typename":"StatusContext","context":"ci/legacy","isRequired":false}]}}}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-optional-statuscontext" "django-test" "$GST_REQUIRED_NAMES"
# No branch protection at all -> nothing required -> no filtering.
GH_FIXTURE="$PR_HEAD"'"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","isRequired":false}]}}}}]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-none-required" "" "$GST_REQUIRED_NAMES"
# An absent rollup (repo with no checks, or an older projection) must yield empty, not an error.
GH_FIXTURE='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]},"reviewRequests":{"totalCount":0,"nodes":[]},"latestOpinionatedReviews":{"nodes":[]}}}}}'
gst_review_for_mr "$DIR" myorg/app 1 github
check "reqnames-absent-rollup" "" "$GST_REQUIRED_NAMES"
check "reqnames-absent-rollup-review" "approved" "$GST_REVIEW"
# Loop-carried-state guard: the names must NOT survive into the next space's lookup. A repo
# with no PR (path/iid empty) returns early — it must still have cleared the previous set,
# or two worktrees of one repo would filter each other's CI by a sibling PR's guards.
GH_FIXTURE="$PR_HEAD$ROLLUP}}}}"
gst_review_for_mr "$DIR" myorg/app 1 github            # populates the names
gst_review_for_mr "$DIR" "" "" github                  # no PR: must reset
check "reqnames-not-loop-carried" "" "$GST_REQUIRED_NAMES"

unset -f gh

# gst_strip_ci_prefix with a review glyph on the MR token (review-state badge)
check "strip-rev-ready"    "inventory"   "$(gst_strip_ci_prefix '🟢 ✅!250 inventory')"
check "strip-rev-changes"  "billing-api" "$(gst_strip_ci_prefix '🔴 💬!88 billing-api')"
check "strip-rev-conflict" "payments"    "$(gst_strip_ci_prefix '🔴 ⚠️!300 payments')"
check "strip-rev-pr"       "web-app"     "$(gst_strip_ci_prefix '🟢 ✅#41 web-app')"
check "strip-rev-noemoji"  "svc"         "$(gst_strip_ci_prefix '✅!7 svc')"
# A user label that merely starts with one of the glyphs (no MR sigil) is preserved:
check "strip-rev-keep"     "✅ done"      "$(gst_strip_ci_prefix '✅ done')"
# Idempotent: re-stripping an already-clean label is a no-op:
check "strip-rev-idem"     "inventory"   "$(gst_strip_ci_prefix "$(gst_strip_ci_prefix '🟢 ✅!250 inventory')")"

# gst_strip_ci_prefix with the 🔀 merged-PR/MR token (positive merged badge)
check "strip-merged-pr"    "dbt"         "$(gst_strip_ci_prefix '🔀#123 dbt')"
check "strip-merged-mr"    "dbt"         "$(gst_strip_ci_prefix '🔀!123 dbt')"
check "strip-merged-full"  "web-app"     "$(gst_strip_ci_prefix '🟢 🔀#42 web-app')"
check "strip-merged-idem"  "dbt"         "$(gst_strip_ci_prefix "$(gst_strip_ci_prefix '🟢 🔀#123 dbt')")"

# gst_pane_cwds — ordered cwds of a workspace's panes (pure; foreground_cwd, else cwd).
panes_ord='{"result":{"panes":[
  {"workspace_id":"wA","foreground_cwd":"/a","cwd":"/A"},
  {"workspace_id":"wA","cwd":"/b"},
  {"workspace_id":"wX","cwd":"/x"}
]}}'
check "pane-cwds-order" "/a,/b" "$(gst_pane_cwds wA "$panes_ord" | paste -sd, -)"
check "pane-cwds-other" "/x"    "$(gst_pane_cwds wX "$panes_ord")"
check "pane-cwds-none"  ""      "$(gst_pane_cwds wZ "$panes_ord")"

# gst_git_has_origin — true only for a git work tree that has an origin remote.
ght="$(mktemp -d)"
git -C "$ght" init -q                                             # git, no origin
gst_git_has_origin "$ght";      check "origin-none"    "1" "$?"
git -C "$ght" remote add origin git@gitlab.com:me/proj.git
gst_git_has_origin "$ght";      check "origin-yes"     "0" "$?"   # git + origin
gst_git_has_origin "$ght/nope"; check "origin-nonrepo" "1" "$?"
gst_git_has_origin "";          check "origin-empty"   "1" "$?"
rm -rf "$ght"

# gst_pick_pane_cwd — prefer the first pane that is a git repo WITH an origin remote, so a
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
check "cwd-git-remote"   "$pt/repo" "$(gst_pick_pane_cwd wA "$pick_json")"
# No pane has a remote -> fall back to the first pane's cwd:
pick_none='{"panes":[{"workspace_id":"wB","cwd":"'"$pt/plug"'"},{"workspace_id":"wB","cwd":"'"$pt/plain"'"}]}'
check "cwd-git-fallback" "$pt/plug" "$(gst_pick_pane_cwd wB "$pick_none")"
# Unknown workspace -> empty:
check "cwd-git-none"     ""         "$(gst_pick_pane_cwd wZ "$pick_json")"
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
check "cwd-skip-plugin" "$pt/repo" "$(GST_PLUGINS_ROOT="$pt/plugins" gst_pick_pane_cwd wC "$pick_plug")"
pick_plug_only='{"panes":[
  {"workspace_id":"wD","cwd":"'"$pt/plugins/github"'"},
  {"workspace_id":"wD","cwd":"'"$pt/plain"'"}
]}'
check "cwd-plugin-fallback" "$pt/plain" "$(GST_PLUGINS_ROOT="$pt/plugins" gst_pick_pane_cwd wD "$pick_plug_only")"
rm -rf "$pt"

# gst_upstream_path — fork checkouts: `upstream` remote on the SAME host as origin -> its
# slug (used to retry PR/MR + CI lookups in the base repo); anything else -> empty.
ut="$(mktemp -d)"
git -C "$ut" init -q
check "up-no-origin"   ""         "$(gst_upstream_path "$ut")"
git -C "$ut" remote add origin git@github.com:me/app.git
check "up-no-upstream" ""         "$(gst_upstream_path "$ut")"
git -C "$ut" remote add upstream git@github.com:core/app.git
check "up-same-host"   "core/app" "$(gst_upstream_path "$ut")"
git -C "$ut" remote set-url upstream https://github.com/core/app
check "up-https-form"  "core/app" "$(gst_upstream_path "$ut")"
git -C "$ut" remote set-url upstream git@gitlab.com:core/app.git
check "up-other-host"  ""         "$(gst_upstream_path "$ut")"
check "up-nonrepo"     ""         "$(gst_upstream_path "$ut/nope")"
rm -rf "$ut"

# gst_daemon_alive — true only when <pidfile> exists and names a live process. Backs the
# poller's is_running check and its self-healing `start` (which relaunches when this is false).
dtmp="$(mktemp)"
echo $$ > "$dtmp"                                   # our own pid -> alive
gst_daemon_alive "$dtmp"; check "daemon-alive-self" "0" "$?"
( exit 0 ) & deadpid=$!; wait "$deadpid" 2>/dev/null # a reaped child -> dead
echo "$deadpid" > "$dtmp"
gst_daemon_alive "$dtmp"; check "daemon-dead-pid"  "1" "$?"
: > "$dtmp"                                          # empty pidfile -> not alive
gst_daemon_alive "$dtmp"; check "daemon-empty"     "1" "$?"
rm -f "$dtmp"                                        # missing pidfile -> not alive
gst_daemon_alive "$dtmp"; check "daemon-nofile"    "1" "$?"

# gst_pid_matches — identity, not just liveness (pid reuse after reboot)
gst_pid_matches $$ "test.sh";           check "pidmatch-self"     "0" "$?"
gst_pid_matches $$ "poller-ctl.sh run"; check "pidmatch-mismatch" "1" "$?"
bash -c 'exit 0' & _dead=$!; wait "$_dead" 2>/dev/null
gst_pid_matches "$_dead" "test.sh";     check "pidmatch-deadpid"  "1" "$?"

# gst_daemon_alive with pattern arg
echo $$ > "$dtmp"
gst_daemon_alive "$dtmp" "test.sh";           check "daemon-alive-pattern"    "0" "$?"
gst_daemon_alive "$dtmp" "poller-ctl.sh run"; check "daemon-reused-pid"       "1" "$?"

# gst_github_checks_status — aggregate a head commit's check runs; the highest-severity
# run decides the overall status (a repo can have many workflows per push, so sampling a
# single run — e.g. a skipped "Claude Code" workflow — misreports CI that is green/running).
# Input lines: status \t conclusion \t id \t url \t updated. Output: winner as canonical \t id \t url \t updated.
check "chk-running-wins" "running	3	u3	t3" "$(printf 'completed\tskipped\t1\tu1\tt1\ncompleted\tsuccess\t2\tu2\tt2\nin_progress\t\t3\tu3\tt3\n' | gst_github_checks_status)"
check "chk-failed-wins"  "failed	2	u2	t2"  "$(printf 'in_progress\t\t1\tu1\tt1\ncompleted\tfailure\t2\tu2\tt2\ncompleted\tsuccess\t3\tu3\tt3\n' | gst_github_checks_status)"
check "chk-success"      "success	2	u2	t2" "$(printf 'completed\tskipped\t1\tu1\tt1\ncompleted\tsuccess\t2\tu2\tt2\n' | gst_github_checks_status)"
check "chk-queued"       "pending	1	u1	t1" "$(printf 'queued\t\t1\tu1\tt1\ncompleted\tskipped\t2\tu2\tt2\n' | gst_github_checks_status)"
check "chk-skipped-only" "skipped	1	u1	t1" "$(printf 'completed\tskipped\t1\tu1\tt1\n' | gst_github_checks_status)"
check "chk-empty"        "" "$(printf '' | gst_github_checks_status)"

# gst_latest_ci looks CI up by the LOCAL HEAD COMMIT, never by branch name. A branch name is
# resolved by the forge, so it answers about whatever that branch points at THERE — a
# different commit whenever local is ahead, on a detached HEAD (GitHub resolves the literal
# ref "HEAD" to the repo's DEFAULT BRANCH), or in a fork whose upstream shares the name.
sht="$(mktemp -d)"
git -C "$sht" init -q -b feature/x
git -C "$sht" remote add origin git@github.com:acme/web-app.git
git -C "$sht" -c user.email=t@t -c user.name=t commit --allow-empty -q -m one
git -C "$sht" -c user.email=t@t -c user.name=t commit --allow-empty -q -m two
shead="$(git -C "$sht" rev-parse HEAD)"
gh() { printf '%s\n' "$*" >> "$GHLOG"; printf '{"data":{"repository":{"object":null}}}'; }

: > "$sht/log"; GHLOG="$sht/log" gst_latest_ci "$sht"
check "sha-branch-resolved"  "feature/x" "$GST_BRANCH"
grep -q "oid=$shead" "$sht/log"
check "sha-queries-head-sha" "0" "$?"
grep -q 'feature/x' "$sht/log"
check "sha-never-branch-name" "1" "$?"

# Detached HEAD: the branch name becomes the literal "HEAD", which the forge would resolve to
# the default branch — the sha keeps the query pinned to the commit actually checked out.
git -C "$sht" checkout -q --detach HEAD~1
sdet="$(git -C "$sht" rev-parse HEAD)"
: > "$sht/log"; GHLOG="$sht/log" gst_latest_ci "$sht"
check "sha-detached-branch"  "HEAD" "$GST_BRANCH"
grep -q "oid=$sdet" "$sht/log"
check "sha-detached-uses-sha" "0" "$?"
grep -q 'oid=HEAD' "$sht/log"
check "sha-detached-not-ref"  "1" "$?"
unset -f gh

# GitLab uses the documented `sha` filter on GET /projects/:id/pipelines ("Return pipelines
# for the specified commit SHA") for the same reason. Untested against a live GitLab.
git -C "$sht" checkout -q feature/x
git -C "$sht" remote set-url origin git@gitlab.com:acme/svc.git
glab() { printf '%s\n' "$*" >> "$GHLOG"; printf '[]'; }
: > "$sht/log"; GHLOG="$sht/log" gst_latest_ci "$sht"
grep -q "pipelines?sha=$shead" "$sht/log"
check "sha-gitlab-uses-sha"  "0" "$?"
grep -q 'pipelines?ref=' "$sht/log"
check "sha-gitlab-not-ref"   "1" "$?"
unset -f glab
rm -rf "$sht"

# The CI verdict comes from GitHub's OWN statusCheckRollup, not from re-aggregating the raw
# check-run list. That is what fixes the case this was written for: on
# Photoroom/photoroom_android@258810c two SCHEDULED workflows (a nightly testing build and a
# Gradle cache warmer) failed against the commit, so aggregating all 27 raw check runs said
# "failed" while GitHub's tick was green — the rollup carries only the 14 runs from the push
# that produced the commit. Re-run attempts collapse the same way.
# Pinned by feeding a response that carries BOTH shapes with opposite verdicts:
BOTH='{"check_runs":[{"name":"nightly","status":"completed","conclusion":"failure","id":9,"html_url":"u","completed_at":"t"}],
  "data":{"repository":{"object":{"statusCheckRollup":{"contexts":{"nodes":[
    {"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","databaseId":1,"detailsUrl":"u1","completedAt":"t1"}]}}}}}}'
check "rollup-wins-over-raw" "success" "$(printf '%s' "$BOTH" \
  | jq -r --arg req "" "$GST_ROLLUP_TSV_JQ" | gst_github_checks_status | cut -f1)"

# GraphQL enums arrive upper-case and must map onto the canonical vocabulary.
mkctx() { printf '{"data":{"repository":{"object":{"statusCheckRollup":{"contexts":{"nodes":[%s]}}}}}}' "$1"; }
rollup_status() { printf '%s' "$1" | jq -r --arg req "${2:-}" "$GST_ROLLUP_TSV_JQ" | gst_github_checks_status | cut -f1; }
check "rollup-enum-failure"  "failed"  "$(rollup_status "$(mkctx '{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE"}')")"
check "rollup-enum-progress" "running" "$(rollup_status "$(mkctx '{"__typename":"CheckRun","name":"a","status":"IN_PROGRESS","conclusion":null}')")"
check "rollup-enum-queued"   "pending" "$(rollup_status "$(mkctx '{"__typename":"CheckRun","name":"a","status":"QUEUED","conclusion":null}')")"
check "rollup-enum-cancel"   "canceled" "$(rollup_status "$(mkctx '{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"CANCELLED"}')")"
check "rollup-empty"         ""        "$(rollup_status '{"data":{"repository":{"object":null}}}')"

# Legacy commit statuses (StatusContext) are part of the rollup and must aggregate like check
# runs — keyed on .context, since they have no .name. Before the rollup switch the plugin read
# an endpoint that could not see them at all.
check "rollup-statusctx-fail"    "failed"  "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"FAILURE"}')")"
check "rollup-statusctx-error"   "failed"  "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"ERROR"}')")"
check "rollup-statusctx-pending" "running" "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"PENDING"}')")"
check "rollup-statusctx-ok"      "success" "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS"}')")"
# ...and they filter by name like check runs, so a required legacy status is no longer invisible:
check "rollup-statusctx-filter"  "failed"  "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"FAILURE"},{"__typename":"CheckRun","name":"opt","status":"COMPLETED","conclusion":"SUCCESS"}')" "ci/legacy")"
check "rollup-statusctx-excluded" "success" "$(rollup_status "$(mkctx '{"__typename":"StatusContext","context":"ci/legacy","state":"FAILURE"},{"__typename":"CheckRun","name":"opt","status":"COMPLETED","conclusion":"SUCCESS"}')" "opt")"

# gst_required_status — only merge-guarding checks decide the CI cell. Modelled on
# Photoroom/content_backend#3397, where "lint / pre_commit" failed while all three required
# checks passed, turning the whole space red for something that could not block the merge.
CR_JSON='{"data":{"repository":{"object":{"statusCheckRollup":{"contexts":{"nodes":[
  {"__typename":"CheckRun","name":"django-test","status":"COMPLETED","conclusion":"SUCCESS","databaseId":1,"detailsUrl":"u1","completedAt":"t1"},
  {"__typename":"CheckRun","name":"lint / pre_commit","status":"COMPLETED","conclusion":"FAILURE","databaseId":2,"detailsUrl":"u2","completedAt":"t2"},
  {"__typename":"CheckRun","name":"fastapi-test","status":"COMPLETED","conclusion":"SKIPPED","databaseId":3,"detailsUrl":"u3","completedAt":"t3"},
  {"__typename":"CheckRun","name":"migrations-checks","status":"COMPLETED","conclusion":"SUCCESS","databaseId":4,"detailsUrl":"u4","completedAt":"t4"}]}}}}}}'
REQ_3="$(printf 'django-test\nfastapi-test\nmigrations-checks')"
# Unfiltered, the failing optional lint wins:
check "req-unfiltered" "failed" "$(printf '%s' "$CR_JSON" \
  | jq -r --arg req "" "$GST_ROLLUP_TSV_JQ" | gst_github_checks_status | cut -f1)"
# Filtered to the merge guards, it does not — and a SKIPPED required check does not veto,
# matching GitHub's merge box:
check "req-filtered"   "success" "$(gst_required_status "$CR_JSON" "$REQ_3" | cut -f1)"
# A required check that IS failing still wins:
check "req-fail-wins"  "failed"  "$(gst_required_status "$CR_JSON" "$(printf 'django-test\nlint / pre_commit')" | cut -f1)"
# Empty name list = "do not filter": prints nothing, caller keeps the unfiltered verdict.
check "req-no-names"   ""        "$(gst_required_status "$CR_JSON" "")"
# None of the required checks has run on this commit yet: also nothing, so the caller falls
# back rather than reporting the branch as having no CI.
check "req-absent"     ""        "$(gst_required_status "$CR_JSON" "not-run-here")"
# A name is matched whole, not as a substring — "test" must not match "django-test".
check "req-exact-name" ""        "$(gst_required_status "$CR_JSON" "test")"

# gst_latest_ci (github) — a commit the remote does not have (never pushed, or force-pushed
# away) comes back from the rollup query as a NULL object with a successful call. That is
# "no CI" (rc 0, empty status), NOT a transient api-error (rc 5): rc 5 makes the poller SKIP
# the workspace, freezing whatever it last published.
lct="$(mktemp -d)"
git -C "$lct" init -q
git -C "$lct" remote add origin git@github.com:acme/web-app.git
git -C "$lct" -c user.email=t@t -c user.name=t commit --allow-empty -q -m x
gh() { printf '{"data":{"repository":{"object":null}}}'; }
gst_latest_ci "$lct"
check "ci-deleted-branch-rc"     "0" "$?"
check "ci-deleted-branch-status" ""  "$GST_STATUS"
unset -f gh; rm -rf "$lct"

# gst_review_for_mr (github) — isDraft:false must survive extraction (jq `//` treats false
# as falsy, so `// empty` would erase it and no non-draft PR could ever get a review state).
gh() { printf '%s' "$GH_STUB"; } # shadows the gh CLI inside gst_review_for_mr
GH_STUB='{"data":{"repository":{"pullRequest":{"isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","reviewThreads":{"nodes":[]}}}}}'
gst_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-nondraft" "approved" "$GST_REVIEW"
GH_STUB='{"data":{"repository":{"pullRequest":{"isDraft":true,"mergeable":"MERGEABLE","reviewDecision":null,"reviewThreads":{"nodes":[]}}}}}'
gst_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-draft"    "draft"    "$GST_REVIEW"
GH_STUB='{"data":{"repository":{"pullRequest":null}}}'
gst_review_for_mr "$PWD" "acme/web-app" 41 github
check "review-gh-missing"  ""         "$GST_REVIEW"
unset -f gh

# Configurable icons — GST_ICON_* overrides (defaults are pinned by the em-*/rg-*/rb-*
# checks above, which run with all icon vars unset).
check "ov-ok"         "X" "$(GST_ICON_OK=X gst_status_emoji success)"
check "ov-fail"       "F" "$(GST_ICON_FAIL=F gst_status_emoji failed)"
check "ov-run"        "R" "$(GST_ICON_RUN=R gst_status_emoji pending)"
check "ov-none"       "N" "$(GST_ICON_NONE=N gst_status_emoji canceled)"
check "ov-approved"   "A" "$(GST_ICON_APPROVED=A gst_review_glyph approved)"
check "ov-draft"      "D" "$(GST_ICON_DRAFT=D gst_review_glyph draft)"
check "ov-conflict"   "C" "$(GST_ICON_CONFLICT=C gst_review_glyph conflict)"
# Set-but-EMPTY hides the glyph (e.g. no dot for "no pipeline"):
check "ov-none-empty" ""  "$(GST_ICON_NONE= gst_status_emoji canceled)"

# Strip round-trip with overrides: label built the way poll_once builds it.
# The token is built the way status_for_repo builds it: "<badge> <sigil><id>" (space between
# the review badge and the id, per the space-before-pr-id change). strip must handle the space
# or the whole "<badge> #12" token accumulates on every poll.
check "ov-strip-roundtrip" "dbt" "$(
  GST_ICON_OK=✔ GST_ICON_APPROVED=A
  gst_strip_ci_prefix "$(gst_status_emoji success) $(gst_review_glyph approved) !12 dbt"
)"
# Same, GitHub sigil + a default (non-override) badge glyph, and idempotent on a doubled token:
check "ov-strip-badge-spaced"  "dbt" "$(gst_strip_ci_prefix "$(gst_review_glyph approved) #12 dbt")"
check "ov-strip-badge-glued"   "dbt" "$(gst_strip_ci_prefix "$(gst_review_glyph approved)#12 dbt")"
# The default emoji must STILL strip while overrides are active, or labels decorated
# before an icon-config change accumulate prefixes on the first poll after it:
check "ov-strip-default"   "dbt" "$(GST_ICON_OK=✔ gst_strip_ci_prefix '🟢 dbt')"
# Empty round-trip: no dot emitted, MR token still stripped:
check "ov-empty-roundtrip" "svc" "$(GST_ICON_NONE= gst_strip_ci_prefix "$(gst_status_emoji unknown)!123 svc")"
# Empty-override guard: an empty pattern must be skipped by strip ("" matches anything —
# here it would eat the leading space of the label):
check "ov-empty-strip"     " x"  "$(GST_ICON_NONE= gst_strip_ci_prefix ' x')"

# gst_ttl_ms — the TTL must outlast the republish period (cycle + sleep), so it is derived
# from the MEASURED cycle, not from the interval alone. Floor covers the first pass.
check "ttl-floor"      "90000"  "$(gst_ttl_ms 0 30)"     # 3*(0+30)=90s -> floor
check "ttl-floor-fast" "90000"  "$(gst_ttl_ms 0 1)"      # 3*(0+1)=3s -> floor wins
check "ttl-measured"   "225000" "$(gst_ttl_ms 45 30)"    # 3*(45+30)=225s, the live cycle
check "ttl-grows"      "450000" "$(gst_ttl_ms 120 30)"   # a slower cycle stretches the TTL

# gst_status_bucket — the token NAME carries the state, because herdr's token style is
# static config: one token cannot change colour per state.
check "bucket-ok"      "ok"   "$(gst_status_bucket success)"
check "bucket-fail"    "fail" "$(gst_status_bucket failed)"
check "bucket-run"     "run"  "$(gst_status_bucket pending)"
check "bucket-run-sch" "run"  "$(gst_status_bucket scheduled)"
check "bucket-none"    "none" "$(gst_status_bucket canceled)"
check "bucket-empty"   "none" "$(gst_status_bucket '')"

# gst_ci_cell — labelled cell, but a glyph hidden by a set-but-empty override stays
# fully hidden instead of rendering a bare "CI".
check "cell-ok"      "CI 🟢" "$(gst_ci_cell success)"
check "cell-fail"    "CI 🔴" "$(gst_ci_cell failed)"
check "cell-ov"      "CI X"  "$(GST_ICON_OK=X gst_ci_cell success)"
check "cell-hidden"  ""      "$(GST_ICON_NONE= gst_ci_cell canceled)"

# gst_review_cell — labelled like the CI cell; a hidden glyph stays fully hidden.
check "rcell-approved" "R ✅" "$(gst_review_cell approved)"
check "rcell-changes"  "R 💬" "$(gst_review_cell changes)"
check "rcell-merged"   "R 🔀" "$(gst_review_cell merged)"
check "rcell-ov"       "R A"  "$(GST_ICON_APPROVED=A gst_review_cell approved)"
check "rcell-hidden"   ""     "$(GST_ICON_AWAITING= gst_review_cell awaiting)"
check "rcell-none"     ""     "$(gst_review_cell '')"

# Token names: one prefix moves every token out of a colliding plugin's way.
check "tok-default"  "gst_ci_ok" "$(gst_token_name ci_ok)"
check "tok-prefixed" "x_ci_ok"   "$(GST_TOKEN_PREFIX=x_ gst_token_name ci_ok)"
check "tok-bare"     "ci_ok"     "$(GST_TOKEN_PREFIX= gst_token_name ci_ok)"

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

# gst_report_tokens — CI and review each publish under the token named for their current
# state and send every sibling state EMPTY (which clears it), so exactly one of each is
# live per space and the user's per-state fg can colour it. All in ONE call: --seq is per
# (workspace, source), so a second call in the same second would be dropped.
: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" \
  gst_report_tokens wX pending changes "#7" 42 9000
check "report-one-call" "1" "$(wc -l < "$ttmp/log" | tr -d ' ')"
grep -q -- '--token gst_ci_run=CI 🟡' "$ttmp/log";        check "report-ci-live-state"    "0" "$?"
grep -q -- '--token gst_ci_ok= --token gst_ci_fail= ' "$ttmp/log"; check "report-ci-siblings-cleared" "0" "$?"
grep -q -- '--token gst_review_changes=R 💬' "$ttmp/log"; check "report-review-live-state" "0" "$?"
grep -q -- '--token gst_review_approved= ' "$ttmp/log";   check "report-review-siblings-cleared" "0" "$?"
grep -q -- '--token gst_pr=#7 --seq 42 --ttl-ms 9000' "$ttmp/log"; check "report-tail" "0" "$?"
# No CI and no PR at all: every token empty, nothing stale left behind.
: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" gst_report_tokens wX "" "" "" 44 9000
grep -q -- '--token gst_ci_none= --token gst_review_conflict=' "$ttmp/log"
check "report-empty-state-clears-all" "0" "$?"

: > "$ttmp/log"
HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" gst_clear_tokens wX 43
for _t in gst_ci_ok gst_ci_fail gst_ci_run gst_ci_none gst_review_conflict \
          gst_review_changes gst_review_draft gst_review_approved gst_review_awaiting \
          gst_review_merged gst_pr; do
  grep -q -- "--clear-token $_t" "$ttmp/log" || { check "clear-covers-$_t" "0" "1"; }
done
check "clear-covers-every-token" "11" "$(grep -o -- '--clear-token' "$ttmp/log" | wc -l | tr -d ' ')"

# poll-once publishes tokens and NEVER renames — the whole point of the migration. The
# fake workspace carries a label decorated by a pre-token version ("🟢 #12 proj"); the old
# code would strip and re-apply it, the token version must leave the label alone.
tctl() { env HERDR_PLUGIN_STATE_DIR="$ttmp/state" HERDR_PLUGIN_CONFIG_DIR="$ttmp" \
             HERDR_BIN_PATH="$ttmp/herdr" TLOG="$ttmp/log" GST_REFRESH=1 \
             bash "$DIR/poller-ctl.sh" "$@"; }

: > "$ttmp/log"; tctl poll-once >/dev/null 2>&1
grep -q -- 'report-metadata wT --source git-status --token gst_ci_ok= --token gst_ci_fail= --token gst_ci_run= --token gst_ci_none= --token gst_review_conflict= --token gst_review_changes= --token gst_review_draft= --token gst_review_approved= --token gst_review_awaiting= --token gst_review_merged= --token gst_pr= --seq' "$ttmp/log"
check "poll-reports-all-tokens" "0" "$?"
check "poll-single-report" "1" "$(grep -c 'report-metadata' "$ttmp/log")"
grep -q -- '--ttl-ms 90000' "$ttmp/log"
check "poll-ttl-floor-applied" "0" "$?"
grep -q 'workspace rename' "$ttmp/log"
check "poll-never-renames" "1" "$?"

: > "$ttmp/log"; GST_TOKEN_PREFIX=x_ tctl poll-once >/dev/null 2>&1
grep -q -- '--token x_ci_ok= .* --token x_review_changes= .* --token x_pr=' "$ttmp/log"
check "poll-honors-token-prefix" "0" "$?"

# restore — the migration path: clear our tokens AND strip the stale label decoration.
: > "$ttmp/log"; tctl restore >/dev/null 2>&1
grep -q -- 'report-metadata wT --source git-status --clear-token gst_ci_ok' "$ttmp/log"
check "restore-clears-tokens" "0" "$?"
grep -q 'workspace rename wT proj' "$ttmp/log"
check "restore-strips-label"  "0" "$?"
rm -rf "$ttmp"

# poller-ctl ensure — restart after unexpected death only
etmp="$(mktemp -d)"
printf '#!/bin/sh\necho "{\\"result\\":{\\"workspaces\\":[]}}"\n' > "$etmp/herdr"
chmod +x "$etmp/herdr"
pctl() { env HERDR_PLUGIN_STATE_DIR="$etmp/state" HERDR_PLUGIN_CONFIG_DIR="$etmp" \
             HERDR_BIN_PATH="$etmp/herdr" GST_REFRESH=1 GST_START_HEAL_SECS=0 \
             bash "$DIR/poller-ctl.sh" "$@"; }

pctl ensure >/dev/null 2>&1
[ -f "$etmp/state/poller.pid" ]; check "ensure-no-pidfile-stays-stopped" "1" "$?"

bash -c 'exit 0' & _dead=$!; wait "$_dead" 2>/dev/null
mkdir -p "$etmp/state"; echo "$_dead" > "$etmp/state/poller.pid"
pctl ensure >/dev/null 2>&1
gst_daemon_alive "$etmp/state/poller.pid" "poller-ctl.sh run"; check "ensure-restarts-dead" "0" "$?"

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
gst_daemon_alive "$etmp/state/poller.pid" "poller-ctl.sh run"; check "ensure-over-foreign-pid-restarted" "0" "$?"
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
