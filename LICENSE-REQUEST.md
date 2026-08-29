# Licence request to the upstream author

**Status:** draft — not yet sent.
**To:** krystof018 (https://github.com/krystof018)
**Re:** https://github.com/krystof018/herdr-git-status

Send this as a GitHub issue on the upstream repo (title: *"Would you consider adding a licence?"*).
Delete this file once a grant is received and the agreed licence is added as `LICENSE`.

---

## Draft issue text

> **Would you consider adding a licence?**
>
> Hi — thanks for building this. I've been running a fork of it daily for a couple of months and
> have built quite a lot on top: GitHub support alongside GitLab, a review-state model, namespaced
> sidebar metadata tokens, reboot-surviving autostart, and a test suite that's now around 240 cases.
>
> I'd like to publish my version as a standalone plugin so other herdr users can install it — the
> herdr marketplace excludes forks, so it would need to be its own repository rather than a fork of
> yours. The blocker is that `herdr-git-status` has no licence file, which means the code is "all
> rights reserved" by default and I have no right to redistribute anything derived from it.
>
> Would you be willing to add a permissive licence — MIT or Apache-2.0 — to the repository? Adding a
> `LICENSE` file to your default branch would be enough. If you'd rather not license the whole
> project, I'd equally welcome a narrower written grant covering redistribution of derivative works.
>
> Either way, I'd keep clear attribution to you and this repository in the README, and I'm happy to
> word that however you prefer. If you'd prefer I didn't publish at all, tell me and I'll keep it
> private — no hard feelings, and thanks again for the original.

---

## Why this is needed (internal note)

| Check | Result |
|---|---|
| GitHub API `license` field on upstream | `null` |
| `LICENSE`/`COPYING` in any upstream commit, any branch | never added |
| Licence grant in upstream README | none |

No licence means all rights reserved. GitHub's Terms of Service §D.5 grants only the right to
**view** a public repository and to **fork it within GitHub** — which covers the existing fork,
running it locally, and pushing to it. It does not grant the right to detach it into a standalone
repository, publish it to a marketplace, or relicense it.

The work here is unambiguously derivative rather than an independent reimplementation:

- `ci-pane.sh`, `open.sh`, and (pre-rename) `mr-pane.sh`, `open-mr.sh` — byte-identical to upstream
- `lib.sh` — 318 of 364 upstream lines still present
- `poller-ctl.sh` — 96 of 130 upstream lines still present

Attribution in the README is good practice but does not substitute for a licence grant.

## If no reply

Options, roughly in order of preference:

1. Keep using it privately as a GitHub fork — fully permitted today, no action needed.
2. Ask again after a reasonable interval, or try another contact route.
3. Rewrite the surviving upstream portions. Note this is *not* a true clean-room rewrite if done
   with the original in view; it reduces legal risk without eliminating it.
