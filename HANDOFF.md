# HANDOFF — omi (deploy/fly)

Personal deploy branch for the Omi Tasting Notes plugin. This branch = the
upstream PR branch (`tasting-notes-plugin`) + `deploy/` + these notes. Nothing
here goes upstream.

Full narrative of how we got here: [`getting_here_2026-10-03.md`](getting_here_2026-10-03.md).

## Resume point (2026-10-03)

**State: working end to end, kept PRIVATE on purpose.**

- **Server:** `https://omi-tasting-notes.fly.dev` — one `shared-cpu-1x`/256 MB
  machine in `yyz`, 1 GB volume `tasting_data` at `/data`. Deploy with
  `bash deploy/deploy.sh` (idempotent; needs `docker` + `fly` logged in).
- **Fly account:** TJ's personal Fly account (owns app `omi-tasting-notes`).
  Not the thomasjankowski.com-domain Fly account — that one has no apps.
- **Omi app:** created in the Omi phone app, **private**, installed on TJ's
  account. External Integration, Trigger = Conversation Creation, webhook
  `/webhook/tasting-candidate`, App Home URL + Chat Tools Manifest URL set,
  all scopes off (intentional — the app never calls Omi back).
- **Verified:** chat tools (log/list/stats/candidates) and the ambient webhook
  both work. A 2026-10-03 recorded tasting produced a candidate.
- **Upstream PR:** [BasedHardware/omi#19942](https://github.com/BasedHardware/omi/pull/19942)
  — open, **APPROVED** (2026-09-30), not merged.

## Open items (owner: TJ unless noted)

1. **Add a card on Fly.** Account is still on the free trial: every machine is
   force-stopped 5 min after start, and the trial ends after 2 VM-hours or
   7 days → app stops serving until a card is added.
2. **Developer Mode webhook:** was set for testing; TJ reports it cleared
   (2026-10-03). If duplicates reappear, check it first.
3. **Stray test file** `/data/claude-selftest.json` on the volume (fake
   candidate under a throwaway uid; invisible to TJ). Harmless. Remove with
   `fly ssh console -a omi-tasting-notes -C "rm /data/claude-selftest.json"`.
4. **Plugin code fixes — ON HOLD** until #19942 merges (don't touch the PR
   before then — let the first merge land, then iterate).
   List: `getting_here_2026-10-03.md` § "Potential PRs".
5. **Going public — deferred.** Preconditions: items 1 + 4 done, a uid/auth
   check, a privacy note. Rationale in the getting-here log.

## Gotchas to remember

- Omi **discards** short conversations (≤100 words go to an LLM keep/discard
  check with a high bar under 2 min). Discarded → app webhook never fires.
  Test with 60–90 s of continuous speech.
- Pressing Stop finalizes immediately; the webhook lands ~5 s later.
- `fly auth login` on a headless box needs a pty and pasting the code back
  (see log). The box is currently logged in to TJ's personal Fly account.
