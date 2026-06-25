# GitLab CI Status — herdr plugin

Surfaces GitLab CI status inside herdr two ways:

1. **Live status dots in the spaces sidebar** — a background poller prefixes each space's label with a
   colored dot for its current branch's pipeline (🟢 passed · 🟡 running · 🔴 failed · ⚪ none). It only
   edits the label text and never touches the agent status dot.
2. **An on-demand detail pane** — project link, current branch, and the latest pipeline status + link.

```
 GitLab CI · gitlab.com/myteam/my-service

 Project   myteam/my-service
           ↗ https://gitlab.com/myteam/my-service
 Branch    feature/checkout-flow

 Pipeline  #1284913   ✓ passed
           ↗ https://gitlab.com/myteam/my-service/-/pipelines/1284913
 Updated   2m ago

 r refresh · q quit · auto-refresh 15s
```

## Requirements

- **herdr** ≥ 0.7
- **glab** (GitLab CLI), authenticated — run `glab auth login`
- **jq**
- **git**

All four must be on your `PATH`. On macOS: `brew install glab jq git`.

## Install

```sh
herdr plugin link /path/to/this/plugin
herdr plugin list        # confirm "gitlab-ci-status" is registered
```

`herdr plugin link` is for local development and runs no build step — none is needed (pure Bash).

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
```

(`prefix` is `ctrl+b`. You can also trigger the actions any time without a keybinding via
`herdr plugin action invoke gitlab-ci-status.<toggle|start|stop|open>`.)

## Usage

**Sidebar dots:** `ctrl+b` then `i` toggles the poller on/off. While on, every space's label gets a
colored CI dot, refreshed every 30s. Toggling off (or `herdr plugin action invoke
gitlab-ci-status.stop`) removes the dots and restores your original labels.

**Detail pane:** `ctrl+b` then `Shift+I` in a GitLab workspace opens a split pane showing the project
link, branch, and latest pipeline. In the pane: **`r`** refresh, **`q`** quit (`Ctrl-C` also closes it).
The branch is re-read every refresh, so switching branches updates automatically.

> **Note on MR pipelines:** status is looked up for the *branch* ref. Projects that run CI only as
> merge-request pipelines (common in some GitLab setups) show ⚪ on a feature branch until it has a branch
> pipeline. An MR-pipeline fallback can be added if you want it.

## Configuration

Optional. Put a `.env` file in the plugin's config dir (honored by both the pane and the poller):

```sh
echo "GITLAB_CI_REFRESH=20" >> "$(herdr plugin config-dir gitlab-ci-status)/.env"
```

- `GITLAB_CI_REFRESH` — refresh interval in seconds (pane default `15`, poller default `30`).

To change keybindings, edit the `[[keys.command]]` entries in your `config.toml` (see above). For pane
placement, edit `herdr-plugin.toml` and re-link.

## How it works

The `open` action reads the workspace's working directory from `HERDR_PLUGIN_CONTEXT_JSON`
(`focused_pane_cwd`, falling back to `workspace_cwd`) and opens the `ci` pane there. The pane derives
the GitLab host and project path from `git remote get-url origin`, reads the current branch, and calls
`glab api "projects/<path>/pipelines?ref=<branch>"` (glab supplies authentication and the host). The
plugin stores no tokens of its own.

The poller (`poller-ctl.sh run`, launched detached by the `start`/`toggle` actions) loops every
`GITLAB_CI_REFRESH` seconds: for each space it finds a pane cwd via `herdr pane list`, fetches the
pipeline the same way, maps the status to a dot, and `herdr workspace rename`s the space to
`"<dot> <original label>"`. The original label is recovered each cycle by stripping any existing CI
dot, so it is idempotent and survives your own renames. `stop` kills the loop and restores all labels.

## Files

| File | Purpose |
|------|---------|
| `herdr-plugin.toml` | Manifest: actions (`open`/`start`/`stop`/`toggle`), the `ci` pane, and keybindings. |
| `poller-ctl.sh` | Always-live poller maintaining the colored CI dot on each space label: `start`/`stop`/`toggle`/`status`. |
| `open.sh` | Resolves the repo dir from workspace context and opens the detail pane. |
| `ci-pane.sh` | The detail pane's live fetch → render → sleep loop (`GITLAB_CI_ONCE=1` for one-shot output). |
| `lib.sh` | Shared helpers: remote parsing, URL-encoding, status glyph/emoji, relative time, pipeline fetch, env loader. |
| `test.sh` | Unit tests for `lib.sh`. Run with `bash test.sh`. |
