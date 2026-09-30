# Deploying Tasting Notes to Fly.io

Cheapest honest always-on home for the Python app: ~$2/mo for a
`shared-cpu-1x` / 256 MB machine in Toronto (`yyz`). Fly.io has no free tier
for new accounts (withdrawn Oct 2024), so budget the two dollars.

All commands run from the repo root, on the `deploy/fly` branch
(which is the upstream PR branch plus this `deploy/` directory).

## 0. Build and push the image (once per app change)

The Dockerfile needs the repo's `plugins/` directory as its build context
so the sibling `omi-plugin-sdk` checkout resolves `../omi-plugin-sdk`:

```bash
# tag with the short SHA so deploys are immutable; also move :latest
SHA=$(git rev-parse --short HEAD)
docker build -t ghcr.io/thomasthinks/omi-tasting-notes:$SHA \
  -f plugins/omi-tasting-notes-app/Dockerfile plugins/
docker tag ghcr.io/thomasthinks/omi-tasting-notes:$SHA \
  ghcr.io/thomasthinks/omi-tasting-notes:latest
echo $GITHUB_TOKEN | docker login ghcr.io -u thomasthinks --password-stdin
docker push ghcr.io/thomasthinks/omi-tasting-notes:$SHA
docker push ghcr.io/thomasthinks/omi-tasting-notes:latest
```

(`buildah bud`/`buildah push` work too.) The GHCR package must be **public**
so Fly can pull it; flip it at
`github.com/thomasthinks?tab=packages` after the first push.

## 1. One-time Fly setup

```bash
# Install flyctl: https://fly.io/docs/flyctl/install/
fly auth login

# If "omi-tasting-notes" is taken, pick your own name and update deploy/fly.toml.
fly apps create omi-tasting-notes

# 1 GB persistent volume for the JSON tasting store (smallest size).
# Volumes are per-machine: this app must run as a SINGLE machine, or one
# user's data splits across disks.
fly volumes create tasting_data --size 1 --region yyz --app omi-tasting-notes

# Shared IPv4 is fine for an HTTPS webhook receiver (no dedicated-IP fee).
fly ips allocate-v4 --shared --app omi-tasting-notes
```

## 2. Deploy

```bash
fly deploy --config deploy/fly.toml --image ghcr.io/thomasthinks/omi-tasting-notes:$SHA
```

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

Then exercise one tool and the webhook shape against the live service
(see the PR thread for the exact curl probes).

## 4. Wiring it to Omi

1. **Chat tools:** in the Omi app-store submission (or Developer Mode), point
   the app at `https://omi-tasting-notes.fly.dev`. Omi discovers the tools via
   `/.well-known/omi-tools.json`.
2. **Ambient webhook:** set the conversation webhook URL to the **bare** URL
   `https://omi-tasting-notes.fly.dev/webhook/tasting-candidate` — Omi
   appends `?uid=<omi-user-id>` itself; don't add it.

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
