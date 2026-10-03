#!/usr/bin/env bash
# One-shot deploy of the Tasting Notes plugin to Fly.io.
#
# Run from the repo root on the deploy/fly branch:
#   bash deploy/deploy.sh
#
# Safe to re-run: every step after the docker build is idempotent and skips
# work that's already done (existing app, volume, allocated IP, etc.).
#
# Prerequisites on PATH: docker, flyctl (as `fly`, authenticated).
# The image is pushed to Fly's own registry (registry.fly.io), so no GitHub
# token scope or public-package step is needed.

set -euo pipefail

APP="omi-tasting-notes"
REGION="yyz"
IMAGE="registry.fly.io/$APP"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

say() { printf '\n==> %s\n' "$*"; }

# --- 0. prerequisites -------------------------------------------------------
say "checking prerequisites"
for cmd in docker fly; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found on PATH"; exit 1; }
done
fly auth whoami >/dev/null 2>&1 || { echo "ERROR: 'fly' is not authenticated (run: fly auth login)"; exit 1; }
echo "ok: docker, fly ($(fly auth whoami))"

# --- 1. build ---------------------------------------------------------------
SHA="$(git rev-parse --short HEAD)"
say "building $IMAGE:$SHA"
docker build -t "$IMAGE:$SHA" -f plugins/omi-tasting-notes-app/Dockerfile plugins/
docker tag "$IMAGE:$SHA" "$IMAGE:latest"

# --- 2. fly app (idempotent) -----------------------------------------------
say "ensuring app"
if fly status --app "$APP" >/dev/null 2>&1; then
  echo "app '$APP' already exists, skipping"
else
  fly apps create "$APP"
fi

# --- 3. push to Fly registry ------------------------------------------------
say "pushing to registry.fly.io"
fly auth docker
docker push "$IMAGE:$SHA"
docker push "$IMAGE:latest"

# --- 4. fly volume (idempotent) ---------------------------------------------
say "ensuring volume"
if fly volumes list --app "$APP" 2>/dev/null | grep -q tasting_data; then
  echo "volume 'tasting_data' already exists, skipping"
else
  fly volumes create tasting_data --size 1 --region "$REGION" --app "$APP" --yes
fi

# --- 5. fly IPv4 (idempotent) -----------------------------------------------
say "ensuring public IPv4"
if fly ips list --app "$APP" 2>/dev/null | grep -qE '\bv4\b'; then
  echo "IPv4 already allocated, skipping"
else
  fly ips allocate-v4 --shared --app "$APP" --yes
fi

# --- 6. deploy --------------------------------------------------------------
# --ha=false: single machine only, the data volume can't be shared.
say "deploying to Fly"
cd "$REPO_ROOT/deploy"
fly deploy --image "$IMAGE:$SHA" --ha=false

# --- 7. verify --------------------------------------------------------------
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
