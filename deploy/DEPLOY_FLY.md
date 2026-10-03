# Deploying Tasting Notes to Fly.io

Cheapest honest always-on home for the Python app: ~$2/mo for a
`shared-cpu-1x` / 256 MB machine in Toronto (`yyz`). Fly.io has no free tier
for new accounts (withdrawn Oct 2024), so budget the two dollars.

Everything runs from the repo root, on the `deploy/fly` branch
(which is the upstream PR branch plus this `deploy/` directory).

## 1. Prerequisites (once per box)

```bash
# docker must already be installed.
# Install flyctl (lands in ~/.fly/bin; add it to PATH):
curl -fsSL https://fly.io/install.sh | sh
export PATH="$HOME/.fly/bin:$PATH"

# Log in to the Fly account that owns (or will own) the app.
fly auth login
fly auth whoami   # check it's the right account before deploying
```

No GitHub token is needed: the image goes to Fly's own registry
(`registry.fly.io/omi-tasting-notes`), which is private and authenticated by
the same Fly login.

## 2. Deploy

```bash
bash deploy/deploy.sh
```

Safe to re-run; every step skips work that's already done. What it does:

1. Checks `docker` and `fly` are on PATH and `fly` is logged in.
2. Builds the image with `plugins/` as the build context (so the sibling
   `omi-plugin-sdk` checkout resolves `../omi-plugin-sdk`), tagged with the
   short commit SHA and `:latest`.
3. Creates the Fly app `omi-tasting-notes` if it doesn't exist.
   If that name is taken on fly.dev, change `APP` in `deploy.sh` and `app`
   in `deploy/fly.toml`.
4. Pushes both tags to `registry.fly.io` (`fly auth docker` sets up the login).
5. Creates the 1 GB `tasting_data` volume in `yyz` if missing.
6. Allocates a **shared** IPv4 if missing (no dedicated-IP fee).
7. Runs `fly deploy --image registry.fly.io/omi-tasting-notes:<sha> --ha=false`.
   `--ha=false` keeps it to **one machine**: volumes are per-machine, so a
   second machine would get its own empty disk and split a user's data.
8. Polls `https://omi-tasting-notes.fly.dev/health` for up to 5 minutes and
   prints the start of the tool manifest.

`deploy/fly.toml` keeps one warm machine (`min_machines_running = 1`, so the
ambient webhook never cold-starts), wires `/health` checks, and mounts the
`tasting_data` volume at `/data` (`TASTING_DATA_DIR=/data`).

## 3. Verify

```bash
fly status --app omi-tasting-notes
curl https://omi-tasting-notes.fly.dev/health
# -> {"status":"ok"}
curl https://omi-tasting-notes.fly.dev/.well-known/omi-tools.json | head -c 300
```

## 4. Wiring it to Omi

One Omi app carries both capture paths: the **chat tools** (Omi's AI calls
`/tools/*` when you ask it to log a tasting) and the **ambient webhook** (Omi
posts each finished conversation to `/webhook/tasting-candidate`). You create
it once in the Omi phone app and install it on your own account; it can stay
private.

1. **Open the create form.** Omi phone app → **Explore** tab →
   **Create an App**. (No Explore tab? Settings → Connect Device first.)
2. **Basics.** App Name `Tasting Notes`, any icon, Category (e.g.
   Productivity), and a one-line description, e.g. "Log structured tasting
   notes for wine, coffee, whiskey, and beer."
3. **Capabilities.** Tick **External Integration** only. That opens the
   External Integration section below.
4. **Fill the External Integration section exactly:**

   | Field | Value |
   |---|---|
   | Trigger Event | **Conversation Creation** |
   | Webhook URL* | `https://omi-tasting-notes.fly.dev/webhook/tasting-candidate` |
   | App Home URL | `https://omi-tasting-notes.fly.dev` |
   | Chat Tools Manifest URL | `https://omi-tasting-notes.fly.dev/.well-known/omi-tools.json` |
   | Setup Instructions | leave blank |
   | Auth URL | leave blank |
   | Setup Completed URL | leave blank |

   - **Webhook URL is bare.** Omi appends `?uid=<your-omi-user-id>` itself;
     adding it yourself breaks the call.
   - **App Home URL is required in practice.** The manifest lists tool
     endpoints as relative paths (`/tools/log_tasting`, …); Omi resolves them
     against App Home URL. Leave it blank and the tools register with no host.
   - Omi fetches the manifest when you save. If you later change the tool
     list, re-save the app to refresh it.
5. **Visibility.** Leave **Make my app public** off. Public means a store
   listing and Omi's review; a private app works for you immediately.
   (There's no auth: anyone who knows a uid can read that user's tastings, so
   don't publish without adding auth.)
6. **Submit App**, then open it from Explore (**Created by me** / the **My Apps** filter)
   and tap **Install App**.
7. **Test the chat tools.** In Omi chat: "log a tasting: 2019 Barolo,
   cherry and tar on the nose, 93 points, buy." Then "show my tasting stats".
   Omi should say it's calling Tasting Notes and answer from the app.
8. **Test the ambient webhook.** Have (or play) a short conversation that
   sounds like a tasting, with scores and buy/skip language. When it ends and
   Omi saves the conversation, ask Omi chat "list my tasting candidates".
   Server side, `fly logs --app omi-tasting-notes` shows the
   `POST /webhook/tasting-candidate?uid=…` hit.

Don't also set Settings → Developer Mode → **Memory Creation Webhook** to the
same URL: that's a separate per-account webhook and would deliver every
conversation twice.

## Notes

- **Single machine only.** The JSON store lives on the `tasting_data` volume
  at `/data`; a second machine would get its own empty volume. Back it up
  with `fly sftp` / `fly ssh console` if you ever care about it.
- **No authentication.** Anyone who knows a uid can read/write that user's
  tastings. Tasting notes are low-sensitivity, but treat uids as secrets.
- **Cost:** one idle 256 MB machine ≈ $2/mo. NA egress is $0.02/GB —
  negligible for webhook traffic.
- This `deploy/` directory is personal deploy config versioned on the
  `deploy/fly` branch. It is deliberately excluded from the upstream PR to
  `BasedHardware/omi`.
