#!/usr/bin/env bash
# One-shot deploy of the Tasting Notes plugin to Fly.io.
#
# Run from the repo root on the deploy/fly branch:
#   bash deploy/deploy.sh
#
# Safe to re-run: every step after the docker build is idempotent and skips
# work that's already done (existing volume, allocated IP, etc.).
#
# Prerequisites on PATH: docker, flyctl (as `fly`), gh (authenticated).
# The GitHub token needs the `write:packages` scope for the GHCR push;
# if the push is denied the script tells you the one-line fix.

set -euo pipefail

APP="omi-tasting-notes"
REGION="yyz"
IMAGE="ghcr.io/thomasthinks/omi-tasting-notes"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

say() { printf '\n==> %s\n' "$*"; }

# --- 0. prerequisites -------------------------------------------------------
say "checking prerequisites"
for cmd in docker fly gh; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found on PATH"; exit 1; }
done
GH_USER="$(gh api user -q .login 2>/dev/null || true)"
[ -n "$GH_USER" ] || { echo "ERROR: 'gh' is not authenticated (run: gh auth login)"; exit 1; }
fly auth whoami >/dev/null 2>&1 || { echo "ERROR: 'fly' is not authenticated (run: fly auth login)"; exit 1; }
echo "ok: docker, fly, gh ($GH_USER)"

# --- 1. build ---------------------------------------------------------------
SHA="$(git rev-parse --short HEAD)"
say "building $IMAGE:$SHA"
docker build -t "$IMAGE:$SHA" -f plugins/omi-tasting-notes-app/Dockerfile plugins/
docker tag "$IMAGE:$SHA" "$IMAGE:latest"

# --- 2. push to GHCR --------------------------------------------------------
say "pushing to GHCR"
echo "$(gh auth token)" | docker login ghcr.io -u "$GH_USER" --password-stdin
if ! docker push "$IMAGE:$SHA" || ! docker push "$IMAGE:latest"; then
  cat >&2 <<'EOF'
ERROR: GHCR push was denied. The GitHub token almost certainly lacks the
'write:packages' scope. Fix it with one command, then re-run this script:

    gh auth refresh -s write:packages

(If that needs a browser approval, do it once; the scope persists.)
EOF
  exit 1
fi
cat <<'EOF'
NOTE: the GHCR package must be PUBLIC for Fly to pull it.
Flip it once at: https://github.com/thomasthinks?tab=packages
EOF

# --- 3. fly volume (idempotent) ---------------------------------------------
say "ensuring volume"
if fly volumes list --app "$APP" 2>/dev/null | grep -q tasting_data; then
  echo "volume 'tasting_data' already exists, skipping"
else
  fly volumes create tasting_data --size 1 --region "$REGION" --app "$APP" --yes
fi

# --- 4. fly IPv4 (idempotent) -----------------------------------------------
say "ensuring public IPv4"
if fly ips list --app "$APP" 2>/dev/null | grep -qE '\bv4\b'; then
  echo "IPv4 already allocated, skipping"
else
  fly ips allocate-v4 --app "$APP" --yes
fi

# --- 5. deploy --------------------------------------------------------------
say "deploying to Fly"
cd "$REPO_ROOT/deploy"
fly deploy

# --- 6. verify --------------------------------------------------------------
say "verifying live deployment"
for _ in $(seq 1 30); do
  if curl -sf "https://$APP.fly.dev/health" >/dev/null 2>&1; then
    echo "HEALTHY: https://$APP.fly.dev/health"
    curl -s "https://$APP.fly.dev/.well-known/omi-tools.json" | head -c 200
    echo
    say "done: $APP is live at https://$APP.fly.dev"
    exit 0
  fi
  sleep 10
done
echo "ERROR: health check timed out. Inspect with:"
echo "  fly status --app $APP"
echo "  fly logs --app $APP"
exit 1
