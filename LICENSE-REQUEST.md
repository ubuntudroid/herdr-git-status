# Licence request to the upstream author

**Status:** BOTH ROUTES SENT. No reply from either. **Decision point 2026-10-03** — if nothing by
then, treat the matter as settled and stop chasing it (see "If no reply").

1. **PR, 2026-08-29:** https://github.com/krystof018/herdr-git-status/pull/14 — "Add MIT license",
   one file, based on `upstream/main` so the diff contains nothing but `LICENSE`. Merging it is the
   only action needed. As of 2026-09-19: open, zero comments, zero reviews.
2. **Email, 2026-09-19:** sent by Sven to `contact@krystofprasil.com` (a real address, taken from the
   commit metadata on `upstream/main` — not a GitHub noreply). Same ask, different channel, on the
   theory that repo notifications are not somewhere he is looking.

**To:** Kryštof Prášil / krystof018 (https://github.com/krystof018), site krystofprasil.cz

No further contact attempts — two channels is enough, and a third would be pestering. Delete this
file once the PR is merged and the licence is reflected in the README.

---

## Draft issue text

> **Would you consider adding a licence?**
>
> Hi — thanks for building this. I've been running a fork of it daily for a couple of months and
> have built quite a lot on top. To be clear about what is yours and what is mine: you built the
> plugin, including its GitHub support alongside GitLab and the review-state mapping for both
> providers. What I added since is namespaced sidebar metadata tokens replacing the label writing,
> merge/auto-merge cells on top of your review model, concurrent space polling, a reboot-surviving
> `ensure` action, and a test suite grown from 97 `check` call sites to 248.
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

Both contact routes are now spent, so option 2 below is closed. From 2026-10-03, default to
option 1 and stop spending attention on this.

1. **Keep it as a GitHub fork — the default.** Fully permitted today, no action needed. Costs almost
   nothing: `herdr plugin install ubuntudroid/herdr-git-status` already works for anyone, so the only
   thing a missing licence actually costs is the marketplace card, and that is gated on herdr policy
   (discussion #3765) rather than on Kryštof.
2. ~~Ask again / another route~~ — spent: PR 2026-08-29, email 2026-09-19.
3. Rewrite the surviving upstream portions. Note this is *not* a true clean-room rewrite if done
   with the original in view; it reduces legal risk without eliminating it.
