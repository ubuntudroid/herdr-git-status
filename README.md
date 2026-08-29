# GitLab & GitHub CI Status — herdr plugin

Surfaces CI status inside herdr — for both **GitLab** (pipelines + merge requests via `glab`) and
**GitHub** (check runs + pull requests via `gh`), auto-detected from each repo's `origin` host — two
ways:

1. **Live status dots in the spaces sidebar** — a background poller publishes **metadata tokens**
   per space: the CI cell `CI <glyph>` (🟢 passed · 🟡 running · 🔴 failed · ⚪ none), the
   review-state glyph, and the request number (`!123` for a GitLab MR, `#123` for a GitHub PR).
   Your space labels are never touched, and neither is the agent status dot. Tokens render only
   where your sidebar layout asks for them — see [Configure the sidebar](#configure-the-sidebar),
   which is a required one-time step.
2. **An on-demand detail pane** — project, current branch, the latest pipeline/run status,
   the open MR/PR, and a list of the most recent **failed** pipelines/runs for the branch
   (up to 5). The project path, each run/pipeline `#id`, and the `!123`/`#123` are clickable
   OSC 8 hyperlinks (Ctrl/Cmd-click) — the raw URLs aren't printed.

```
 GitLab CI · gitlab.com/myteam/my-service

 Project   myteam/my-service          ← links to the project page
 Branch    feature/checkout-flow

 Pipeline  #1284913   ✓ passed        ← #id links to the pipeline
 Updated   2m ago
 MR        !123                       ← links to the merge request

 Recent failures
   #1284901   ✗ 2h ago                ← each #id links to that pipeline
   #1284866   ✗ 5h ago

 r refresh · q quit · auto-refresh 15s
```

…and for a GitHub repo:

```
 GitHub CI · github.com/acme/web-app

 Project   acme/web-app               ← links to the repo
 Branch    feature/checkout-flow

 Run       #28165711782   ✓ passed    ← #id links to the decisive check run
 Updated   2m ago
 PR        #123                       ← links to the pull request

 Recent failures
   #28165700001   ✗ 3h ago            ← each #id links to that run
   #28165611120   ✗ 1d ago

 r refresh · q quit · auto-refresh 15s
```

In the sidebar, those spaces show as `CI 🟢 !123 my-service` and `CI 🟢 R ✅ #123 web-app`.

The **review state** is its own token, one per canonical state, rendered as `R <glyph>`: `⚠️` merge
conflict (needs rebase) · `💬` changes requested / unresolved threads · `📝` draft · `✅` approved &
mergeable · `👀` awaiting review · `🔀` merged. The plugin publishes whichever one applies and clears
the rest; which of them you actually see is decided by your `rows` (see
[Configure the sidebar](#configure-the-sidebar)), not by the plugin.

**Re-requested reviews count.** On GitHub, re-requesting review after addressing feedback hands
the ball back to that reviewer, so the PR reads `👀` awaiting rather than staying at `💬`. This is
per reviewer: a standing "changes requested" verdict is retired only if *its own author* is in the
PR's pending review requests. Another reviewer still having an unanswered request does not retire
it. (GitHub keeps a re-requested reviewer in `latestOpinionatedReviews` *and* `reviewRequests`
simultaneously, so the author comparison is what makes this work — counting standing verdicts
alone pins such a PR to `💬` forever.) The sticky `reviewDecision` and unresolved threads that
outlive a pushed fix likewise only count while nothing at all is pending.

Once the branch's MR/PR is **merged**, the open-request token is replaced by a `🔀` merged badge
(e.g. `🔀#123` / `🔀!123`) — a positive signal that the branch landed, instead of the token
silently disappearing when the MR/PR leaves the open state.

## Requirements

- **herdr** ≥ 0.8 (the `workspace report-metadata` API the sidebar tokens use)
- **jq** and **git**
- A provider CLI for whichever remotes you use, authenticated:
  - **glab** (GitLab CLI) — `glab auth login` — for GitLab repos
  - **gh** (GitHub CLI) — `gh auth login` — for GitHub repos

You only need the CLI for the hosts you actually use (jq + git are always required). On macOS:
`brew install jq git glab gh`. The plugin stores no tokens of its own — it reuses glab/gh auth.

## Install

```sh
herdr plugin link /path/to/this/plugin
herdr plugin list        # confirm "gitlab-ci-status" is registered
```

`herdr plugin link` is for local development and runs no build step — none is needed (pure Bash).

## Configure the sidebar

**Required, once.** herdr renders a token only if your layout asks for it by name — so until you
add these, the poller runs and nothing appears. Add them to `~/.config/herdr/config.toml` and run
`herdr server reload-config`:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  [{ token = "$ci_ok",   fg = "#9ece6a" },      # your theme's green
   { token = "$ci_fail", fg = "#f7768e" },      # …red
   { token = "$ci_run",  fg = "#e0af68" },      # …yellow
   { token = "$ci_none", dim = true },
   { token = "$review_conflict", fg = "#f7768e" },
   { token = "$review_changes",  fg = "#e0af68" },
   { token = "$review_approved", fg = "#9ece6a" },
   { token = "$review_merged",   fg = "#bb9af7" },   # …purple
   { token = "$review_awaiting", dim = true },
   { token = "$review_draft",    dim = true },
   { token = "$mr" },
   "branch", "git_status"],
]
```

**Why one token per state.** herdr's token style is static config — `{ token, fg, bold, dim }`,
with no conditional form — so one token cannot change colour by state. The state therefore lives
in the token *name*: the poller publishes the CI cell under exactly one of `ci_ok` / `ci_fail` /
`ci_run` / `ci_none`, the review glyph under exactly one of the six `review_*` names, and clears
every sibling. Only one entry from each group ever renders, so a long-looking row stays short on
screen. Drop the `fg`s and it all still works, just uncoloured.

**This is also how you choose what to surface.** The plugin has no opinion any more: omit
`$review_draft` and `$review_awaiting` and you get the old "only attention + ready" behaviour;
include them and you can see which PRs are parked with a reviewer.

`fg` takes a strict `#RGB`/`#RRGGBB` literal — herdr does not resolve theme colour names there, so
paste your own theme's hex rather than the values above. A bare `{ token = "$review" }` with no
`fg` follows the theme foreground, which is what you want for glyphs that are already meaningful.

Tokens can go on any row, in any order — put them on the first row if you want them next to the
space name. A row whose every entry is empty is not rendered at all, so adding tokens to a row can
make that row appear on spaces that previously had nothing to show there.

If another plugin already publishes a token with one of these names, set
`GITLAB_CI_TOKEN_PREFIX` (see [Configuration](#configuration)) and use the prefixed names in
`rows` — token names are a single shared namespace across all plugins.

## Keybindings (one-time setup)

herdr 0.7 does **not** bind keys declared in a plugin manifest, so add the bindings to your
`~/.config/herdr/config.toml` and run `herdr server reload-config`:

```toml
[[keys.command]]
key = "prefix+i"
type = "shell"
command = "herdr plugin action invoke gitlab-ci-status.toggle"

[[keys.command]]
key = "prefix+shift+i"
type = "shell"
command = "herdr plugin action invoke gitlab-ci-status.open"

[[keys.command]]
key = "prefix+r"
type = "shell"
command = "herdr plugin action invoke gitlab-ci-status.open-mr"
```

(`prefix` is `ctrl+b`. You can also trigger the actions any time without a keybinding via
`herdr plugin action invoke gitlab-ci-status.<toggle|start|stop|open|open-mr>`.)

## Usage

**Sidebar dots:** `ctrl+b` then `i` toggles the poller on/off. While on, every space gets its
tokens refreshed every 30s. Toggling off (or `herdr plugin action invoke
gitlab-ci-status.stop`) clears them immediately. Tokens also carry a TTL, so if the daemon is
killed or the machine reboots they expire on their own within a few minutes.

**Detail pane:** `ctrl+b` then `Shift+I` in a GitLab or GitHub workspace opens a split pane showing the
project link, branch, latest pipeline/run, and open MR/PR. In the pane: **`r`** refresh, **`q`** quit
(`Ctrl-C` also closes it). The branch is re-read every refresh, so switching branches updates
automatically.

**My MRs pane:** `ctrl+b` then `r` opens a pane listing **your own** open MRs/PRs across every
repo, aggregated from each provider you're authenticated with (GitLab via `glab`, GitHub via
`gh`), in two sections — **Ready to merge** (approved & mergeable) and **Needs action** (changes
requested / unresolved threads, or merge conflict). Each MR id is a clickable OSC 8 link. In the
pane: `r` refresh, `q` quit (Ctrl-C also closes), auto-refresh 15s. Always invokable via
`herdr plugin action invoke gitlab-ci-status.open-mr`.

**Only merge-guarding checks decide the CI cell.** On GitHub, when the branch has an open PR, the
cell aggregates just that PR's *required* status checks — the ones branch protection or a ruleset
makes a merge guard. A failing optional check (a lint job, a coverage bot, a preview deploy) no
longer shows the space as broken when nothing is actually blocking the merge. A `SKIPPED` required
check does not veto, matching GitHub's merge box.

**The cell appears whenever CI ran on the branch's remote head**, whether or not anything gates a
merge — a green `main` is worth seeing. Merge guards only *narrow* the verdict; they are not what
makes the cell appear. So the unfiltered result stands when the branch has no open PR (required-ness
is a per-PR fact), when the PR configures no required checks, when none of the required checks has
run on this commit yet, and when a required check is a **legacy commit status** rather than a check
run — the REST endpoint the plugin reads returns check runs only and never sees a commit status, so
filtering by name there could hide a failing required status and report green while the merge is
blocked.

**No cell at all** when no CI ran on that remote head. Note this is the branch's *remote* head, not
your local one: an unpushed branch has nothing to report, and a fork whose own branch has no runs
reports nothing rather than borrowing the upstream repo's result for a same-named branch.

This costs no extra API call: the required names come from the same PR projection that resolves the
review state. GitLab is unaffected (its merge model has no equivalent per-check required flag), and
the **detail pane still shows every check** — that is where you go to see what actually broke.

> **Note on branch vs MR/PR pipelines:** status is looked up for the current *branch* (GitLab pipelines
> by `ref`; GitHub aggregates all check runs on the branch head — the most severe one wins, so one
> skipped workflow can't mask a green or running push). GitLab projects that run CI only as merge-request
> pipelines (common in some GitLab setups) show ⚪ on a feature branch until it has a branch pipeline.

## Autostart after reboot

The poller is a detached daemon: it survives herdr restarts but dies with the
machine. The `ensure` action restarts it only if it died unexpectedly (a
leftover pidfile with a dead process). A deliberate `stop` removes the pidfile,
so `ensure` never overrides it.

Wire `ensure` to your service manager so it fires when the herdr server comes
up — event-driven, no timers, cannot block sleep:

**macOS (launchd)** — `~/Library/LaunchAgents/dev.you.herdr-git-status-ensure.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.you.herdr-git-status-ensure</string>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>-c</string>
    <string>test -S "$HOME/.config/herdr/herdr.sock" &amp;&amp; exec /absolute/path/to/herdr plugin action invoke gitlab-ci-status.ensure || true</string>
  </array>
  <key>WatchPaths</key><array><string>/Users/you/.config/herdr/herdr.sock</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

WatchPaths and the herdr command path need absolute paths (launchd expands nothing). For the command path, substitute the output of `command -v herdr` so it uses your actual herdr binary, not the minimal PATH. Load it with
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<name>.plist`.

**Linux (systemd user units)**:

```ini
# ~/.config/systemd/user/herdr-git-status-ensure.path
[Path]
PathExists=%h/.config/herdr/herdr.sock
[Install]
WantedBy=default.target

# ~/.config/systemd/user/herdr-git-status-ensure.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/env herdr plugin action invoke gitlab-ci-status.ensure
```

Enable with `systemctl --user enable --now herdr-git-status-ensure.path`.
The service stays active after the first trigger, ensuring the poller survives herdr restarts during the login session.

If the poller crashes while herdr keeps running, nothing re-fires until the
next herdr start — restart manually or add a timer if that ever matters.

## Configuration

Optional. Put a `.env` file in the plugin's config dir (honored by both the pane and the poller):

```sh
echo "GITLAB_CI_REFRESH=20" >> "$(herdr plugin config-dir gitlab-ci-status)/.env"
```

- `GITLAB_CI_REFRESH` — refresh interval in seconds (pane default `15`, poller default `30`).
- `GITLAB_CI_ICON_OK` / `_FAIL` / `_RUN` / `_NONE` — sidebar CI dot per state
  (defaults `🟢` `🔴` `🟡` `⚪`). Set a var to *empty* to hide that dot. `_NONE` covers runs that
  finished without a verdict — canceled, skipped, manual, unknown; a branch with no CI at all on its
  remote head shows no cell regardless of this setting.
- `GITLAB_CI_TOKEN_PREFIX` — prepended to every sidebar token name (`ci_ok`, `ci_fail`, `ci_run`,
  `ci_none`, `review_conflict`, `review_changes`, `review_draft`, `review_approved`,
  `review_awaiting`, `review_merged`, `mr`). Token names are one namespace shared by all plugins,
  so set this if another plugin already publishes one of those names — then mirror the prefix in
  `ui.sidebar.spaces.rows`. Default empty.
- `GITLAB_CI_ICON_CONFLICT` / `_CHANGES` / `_APPROVED` / `_DRAFT` / `_AWAITING` / `_MERGED` —
  review-state glyphs (defaults `⚠️` `💬` `✅` `📝` `👀` `🔀`). Each state has its own sidebar
  token, so which of them appear is up to your `rows`.

Example — GitHub's own octicons instead of emoji, so the sidebar matches what GitHub shows on the
PR page (needs a Nerd-patched terminal font, otherwise these render as tofu boxes). Codepoints are
`nf-oct-*` from Nerd Fonts v3. The glyphs are given as codepoints rather than literal characters
because they do not survive copy-paste through every editor — write them with
`perl -CSD -e 'print "GITLAB_CI_ICON_OK=\x{F4A4}\n"'` or your editor's insert-codepoint command.

```sh
# CI cell — one dot for every state, as in GitHub's commit-status dot. Colour carries
# the state, so the glyph does not have to (see Configure the sidebar):
#   OK / FAIL / RUN   nf-oct-dot_fill   U+F444
#   NONE              leave empty for no cell at all, or nf-oct-skip U+F517
#
# If your rows do NOT colour the ci_* tokens, use distinct glyphs instead, matching
# GitHub's check-status icons:
#   OK    nf-oct-check_circle_fill      U+F4A4
#   FAIL  nf-oct-x_circle_fill          U+F530
#   RUN   nf-oct-dot_fill               U+F444

# Review cell, matching GitHub's merge box and Reviewers list:
#   CONFLICT  nf-oct-alert_fill               U+F40C   (filled, matching the dots)
#   CHANGES   nf-oct-file_diff                U+F4D2
#   DRAFT     nf-oct-git_pull_request_draft   U+F4DD
#   APPROVED  nf-oct-check                    U+F42E
#   AWAITING  nf-oct-dot_fill                 U+F444   (GitHub's "review required")
#   MERGED    nf-oct-git_merge                U+F419
```

`dot_fill` deliberately does a lot of work here — every CI state plus "review required" — because
that is how GitHub's own status dots read. What separates the cells is the `CI` and `R` prefixes;
what separates the states within a cell is colour. That trade is only sound if your rows actually
colour the tokens, hence the uncoloured fallback above.

The set above is filled wherever the octicons offer a filled form: `dot_fill`, `alert_fill`. Outline
counterparts exist if you prefer the lighter weight — `dot` U+F4C3 · `alert` U+F421 (GitHub's own
merge-conflict icon is the outline one) · `check_circle` U+F49E · `x_circle` U+F52F · `skip` U+F517.
There is no fill variant of `file_diff`, `check`, `git_merge`, or `git_pull_request_draft` — the
octicon set has only 19 `_fill` glyphs in total, so a wholly filled set is not achievable.

**Colours pair with these glyphs in `ui.sidebar.spaces.rows`, not in the plugin.** Following
GitHub's own status semantics: red for conflict *and* changes-requested (they differ by glyph, as
on GitHub), yellow for anything pending (CI running and review-required alike), green for
passing/approved, purple for merged, and theme-default for draft and "no pipeline".

To change keybindings, edit the `[[keys.command]]` entries in your `config.toml` (see above). For pane
placement, edit `herdr-plugin.toml` and re-link.

## How it works

The `open` action reads the workspace's working directory from `HERDR_PLUGIN_CONTEXT_JSON`
(`focused_pane_cwd`, falling back to `workspace_cwd`) and opens the `ci` pane there. The pane parses the
`origin` remote, picks a provider from the host (`*gitlab*` → glab, `*github*` → gh), reads the current
branch, and queries that provider for the latest CI run and the open MR/PR:

- **GitLab:** `glab api "projects/<path>/pipelines?ref=<branch>"` (latest + a second call
  with `&status=failed` for the recent-failures list) and
  `glab api "projects/<path>/merge_requests?source_branch=<branch>&state=opened"`.
- **GitHub:** `gh api "repos/<owner>/<repo>/actions/runs?branch=<branch>"` (latest + a second
  call with `&status=failure` for the recent-failures list) and
  `gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=open"`.

glab/gh supply authentication and the host; the plugin stores no tokens of its own.

The poller (`poller-ctl.sh run`, launched detached by the `start`/`toggle` actions) loops every
`GITLAB_CI_REFRESH` seconds: for each space it finds a pane cwd via `herdr pane list`, fetches the
latest run and open MR/PR the same way, and publishes the result with
`herdr workspace report-metadata --source gitlab-ci-status --token …`. Labels are never written, so
this plugin cannot collide with another that decorates them.

Every token goes in one call, because `--seq` is tracked per (workspace, source) and a report whose
seq is not greater than the last accepted one is silently ignored. The seq is epoch seconds rather
than a per-start counter, so a daemon restart does not start emitting values herdr will drop. The CI
cell is published under the current state's `ci_*` token and the review glyph under the current
state's `review_*` token, with every sibling state sent empty, which clears it — that is how
exactly one CI token and one review token stay live per space as the state changes.

Tokens carry a TTL and herdr expires them itself, which is why the poller republishes every tick
rather than only on change — publishing on change alone would let the sidebar blank while a repo is
quiet. The TTL is self-tuned to three times the measured poll cycle plus the interval (floor 90s),
since the cycle is network-bound and grows with the number of spaces. Its real job is clearing the
tokens when the daemon dies. `stop` clears them explicitly instead of waiting.

A transient provider error leaves that space unpublished for the tick, so the previous value rides
out its TTL instead of the dot blanking on one failed API call.

On startup the daemon also runs one idempotent label-cleanup pass, which strips decorations left
behind by versions of this plugin that wrote the label. `restore` runs the same pass on demand.

## Files

| File | Purpose |
|------|---------|
| `herdr-plugin.toml` | Manifest: actions (`open`/`open-mr`/`start`/`stop`/`toggle`), the `ci` and `mr` panes, and keybindings. |
| `poller-ctl.sh` | Always-live poller publishing the `ci`/`mr` sidebar tokens: `start`/`stop`/`toggle`/`ensure`/`status`/`poll-once`/`restore`. |
| `open.sh` | Resolves the repo dir from workspace context and opens the detail pane. |
| `ci-pane.sh` | The detail pane's live fetch → render → sleep loop (`GITLAB_CI_ONCE=1` for one-shot output). |
| `open-mr.sh` | Resolves the repo context and opens the "My MRs" pane. |
| `mr-pane.sh` | The "My MRs" pane: my open MRs/PRs across providers, grouped ready / needs-action. |
| `lib.sh` | Shared helpers: remote parsing, provider detection, GitLab/GitHub CI + MR/PR fetch, recent-failures fetch, provider-aware pane label, status glyph/emoji, relative time, hyperlink, env loader, sidebar token reporting. |
| `test.sh` | Unit tests for `lib.sh`. Run with `bash test.sh`. |
