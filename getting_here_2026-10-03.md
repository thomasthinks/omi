# Getting here — Omi Tasting Notes, through 2026-10-03

What was built, how it got deployed, what broke along the way, and what's
parked. Companion to [`HANDOFF.md`](HANDOFF.md) (current state + next steps).

## 1. Background

- **Goal:** build great apps and plugins on the Omi ecosystem, starting with
  these initial merges into [BasedHardware/omi](https://github.com/BasedHardware/omi)
  to get a feel for how things work. The live deployment is proof that this
  one works end to end.
- **The plugin:** `plugins/omi-tasting-notes-app/` — a FastAPI app that turns
  wine/coffee/whiskey/beer tastings into structured cards. Two capture paths:
  - *Chat tools* (explicit): Omi's assistant calls `/tools/*` (log, list,
    get, stats, list/confirm candidates), discovered via
    `/.well-known/omi-tools.json`.
  - *Ambient webhook* (implicit): Omi POSTs each finished conversation to
    `/webhook/tasting-candidate?uid=…`; the app scores the transcript against
    a weighted tasting vocabulary (threshold 8) and stores strong matches as
    `needs_review` candidates.
  - Storage: one JSON file per user under `TASTING_DATA_DIR`. No auth.

## 2. Timeline

| When | What |
|---|---|
| 2026-09-30 | PR [#19942](https://github.com/BasedHardware/omi/pull/19942) opened from `thomasthinks/omi:tasting-notes-plugin`. Two review rounds addressed (null-tolerant params, SDK `Conversation` webhook model, `list_candidates`, working Dockerfile, bare webhook URL, build-context ignore). Community reviewer called it "one of the more careful community plugin submissions"; maintainer **approved** ("feature, approve-only per policy; 45/45 hermetic tests"). Still open/unmerged as of 2026-10-03. |
| 2026-09-30 | `deploy/fly` branch created: PR branch + `deploy/` (fly.toml, runbook). |
| 2026-10-03 | `deploy/deploy.sh` written (one-shot deploy), then reviewed, fixed, and run from `axp-dev` in this session — see §3. |

## 3. This session (2026-10-03) — summary

Run from a semi-transient Claude Code session on `axp-dev` on TJ's behalf
(TJ driving from the Omi phone app).

1. **Cloned** `thomasthinks/omi` branch `deploy/fly` → `~/projects/omi`
   (~1.4 GB; the full Omi monorepo).
2. **Reviewed `deploy.sh` before running** — found four problems (§4.1).
3. **Installed flyctl** (`~/.fly/bin`), logged in. First login hit the wrong
   Fly account (the thomasjankowski.com one, no apps); re-authed to TJ's
   personal account, which already had app `omi-tasting-notes` (pending,
   shared IPv4, no volume, no machines).
4. **Fixed and ran the deploy** (commit `e5063b6`): push to Fly's registry
   instead of GHCR, `--ha=false`, ensure-app step, `--shared` IPv4. Deploy
   created the volume and one machine; `/health` → `{"status":"ok"}`.
5. **Docs:** rewrote `deploy/DEPLOY_FLY.md` to match the script and spelled
   out the Omi wiring step by step from the Omi app source (`840b4a7`,
   `23ea497`).
6. **Wired Omi:** TJ created the private app in the Omi phone app and
   installed it.
7. **Chat tools verified:** `log_tasting` ×2 (Barolo 93, Cabernet Sauvignon
   89/buy), `list_tastings`, `tasting_stats`, `list_candidates` — all 200,
   data confirmed on the volume.
8. **Machine kept stopping** → set `auto_stop_machines = "off"` and redeployed
   (`6102555`). It still stopped: the real cause is the Fly free trial (§4.2).
9. **Ambient webhook debugging** (most of the session) — §4.3. Ended with a
   60 s+ recorded tasting producing candidates.
10. **Decided: keep the app private** (§6).

## 4. Issues walked into

### 4.1 `deploy.sh` as originally written

| Problem | Effect | Fix |
|---|---|---|
| No `fly apps create` step | First run dies at the volume step | Idempotent ensure-app step |
| `fly ips allocate-v4` without `--shared` | Dedicated IPv4, ~$2/mo extra | `--shared` |
| `fly deploy` without `--ha=false` | First deploy may start 2 machines → tasting data split across two volumes | `--ha=false` |
| GHCR push | Needed `write:packages` token scope + manual "make package public" step | Push to `registry.fly.io` (private, uses the Fly login) |

### 4.2 Fly

- **Headless login:** `fly auth login` refuses without a TTY. Workaround: run
  it under `script` (pseudo-terminal) with stdin from a FIFO, send TJ the
  URL, write the code he pastes back into the FIFO.
- **Wrong account first:** the box logged in to the thomasjankowski.com Fly
  account (no apps). Logged out and re-authed.
- **Machine stops after exactly 300 s** (`requested_stop=true` from flyd),
  even with `auto_stop_machines="off"` and `min_machines_running=1`. Cause:
  **Fly free trial** stops all machines 5 min after start; the trial ends
  after 2 VM-hours or 7 days. Requests wake the machine in ~1–3 s, so it
  still works, just with a cold start. Fix: add a card (TJ). Sources:
  docs.fly.io/about/free-trial, community.fly.io thread "flyd issues
  requested_stop at exactly t+300s … during free trial".
- **Health-check "failed" lines** right after each wake are boot timing,
  not a fault (passes ~1 s later).

### 4.3 Omi

- **Docs are stale vs the app.** No "Explore" tab any more — apps live under
  Settings → Integrations (Create your own app; Installed-apps and Filters →
  "Created by me" buttons by the search bar). The per-conversation
  "Developer Tools → trigger webhook" option no longer exists.
- **GitHub Repository URL is mandatory** for External Integration apps
  (client-side check only; backend just stores it). Used
  `…/tree/tasting-notes-plugin/plugins/omi-tasting-notes-app`.
- **App Home URL is required in practice** — the manifest's relative tool
  endpoints are resolved against it.
- **"No candidates" confusion:** chat-logged tastings go straight to
  *tastings*; *candidates* only come from the ambient webhook.
- **Webhook never fired for test recordings — root cause: Omi discards
  short conversations.** From Omi's backend: ≤100 words → LLM keep/discard
  check; under 2 min it keeps only "clearly actionable" content. Discarded
  conversations vanish from the list and **skip app webhooks**. The test
  recordings were 29 s and 37 s (Omi debug log), not the ~40 s+ they felt
  like. The Developer Mode webhook *does* fire for discarded conversations
  (no discard check), which is why single, candidate-less webhooks showed up.
  A 60 s+ recording was kept → both webhooks fired → candidates stored.
- **Stop finalizes immediately;** webhook arrives ~5 s after Stop (no 2-min
  wait when you press Stop).
- **Reprocess does not re-fire webhooks** (backend skips them on reprocess).
- **"Transcript Processed" trigger is the wrong fit** — it streams partial
  segments in a different payload shape; our endpoint expects a full
  Conversation.

## 5. Potential PRs (all ON HOLD until #19942 merges)

Found by the first real recorded tasting (Barolo + Pinot Grigio, one
conversation). All in `plugins/omi-tasting-notes-app/main.py`.

| # | Issue | Size | Note |
|---|---|---|---|
| P1 | **No dedupe on `conversation_id`** — same conversation stored twice (Dev Mode + app webhook). Omi's finalizer can also retry deliveries. | Small | Skip if a candidate with that `conversation_id` exists. |
| P2 | **Score missed:** "a score of 92" not parsed (regex wants "points", "/100", "out of 100"). | Small | Accept "score of N" / "N out of 100" variants. |
| P3 | **One verdict per conversation, skip wins:** Barolo "buy" overridden by Pinot Grigio skip language → `skip`. STT also rendered "recommend to buy" as "a record to buy". | Moderate | Per-segment verdicts, or prefer the verdict nearest a score. |
| P4 | **Multiple wines → one unnamed candidate.** | Design change | Needs splitting/extraction (likely an LLM), not keywords. |
| P5 | **Non-atomic save:** `_save_user` rewrites the file in place; a read error loads as empty, so a kill mid-write can wipe a user's history on the next save. | Small | Write to temp file + `os.replace`. |
| P6 | **No auth:** any caller with a uid can read/write that user's data (verified with plain `curl`). | Moderate | Required before going public. |

## 6. Decision: keep the Omi app private (2026-10-03)

TJ considered making it public "to gather some data". Held off because:
no auth (P6); public use stores strangers' conversation excerpts (500 chars
per candidate) with no privacy policy, under TJ's name; the trial would take
it offline in front of users/reviewers; and P1–P3 would be the first thing an
Omi reviewer sees — better to ship it once those are fixed.

Revisit after #19942 merges, with: card added, P1–P3 + P5 fixed, a uid/auth
check, and a short privacy note.

## 7. Commits on `deploy/fly` this session

- `e5063b6` deploy.sh: push to Fly registry, single machine, ensure app + shared IPv4
- `840b4a7` DEPLOY_FLY.md: match deploy.sh; detail Omi wiring
- `23ea497` DEPLOY_FLY.md: note the mandatory GitHub Repository URL field
- `6102555` fly.toml: auto_stop_machines off
- (this commit) HANDOFF.md + this log
