# GitLab CI Status — herdr plugin

Live GitLab project link and CI pipeline status for the current workspace, shown in a herdr pane.

Press a key in any workspace whose repo lives on GitLab and a side pane opens showing the project
link, the current branch, and the latest CI pipeline's status (colored) with a link to it. The pane
refreshes itself every few seconds.

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

## Usage

In a workspace opened on a GitLab repo, press **`ctrl+b`** then **`g`**. A split pane opens on the right.

In the pane:

- **`r`** — refresh now
- **`q`** — quit (`Ctrl-C` also closes it)

The current branch is re-read on every refresh, so switching branches updates the pane automatically.

## Configuration

Optional. Put a `.env` file in the plugin's config dir:

```sh
echo "GITLAB_CI_REFRESH=10" >> "$(herdr plugin config-dir gitlab-ci-status)/.env"
```

- `GITLAB_CI_REFRESH` — auto-refresh interval in seconds (default `15`).

To change the keybinding or pane placement, edit `herdr-plugin.toml` and re-link.

## How it works

The `open` action reads the workspace's working directory from `HERDR_PLUGIN_CONTEXT_JSON`
(`focused_pane_cwd`, falling back to `workspace_cwd`) and opens the `ci` pane there. The pane derives
the GitLab host and project path from `git remote get-url origin`, reads the current branch, and calls
`glab api "projects/<path>/pipelines?ref=<branch>"` (glab supplies authentication and the host). The
plugin stores no tokens of its own.

## Files

| File | Purpose |
|------|---------|
| `herdr-plugin.toml` | Manifest: the `open` action, the `ci` pane, and the `prefix+g` keybinding. |
| `open.sh` | Resolves the repo dir from workspace context and opens the pane. |
| `ci-pane.sh` | The live fetch → render → sleep loop (supports `GITLAB_CI_ONCE=1` for one-shot output). |
| `lib.sh` | Pure helpers: remote parsing, URL-encoding, status glyphs, relative time. |
| `test.sh` | Unit tests for `lib.sh`. Run with `bash test.sh`. |
