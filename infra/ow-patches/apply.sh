#!/usr/bin/env bash
# Re-apply the Whoop workout-sync fix to the self-hosted Open Wearables VM.
#
# WHY THIS EXISTS: OW's workout save path crashed on an SQLAlchemy after-commit
# webhook (session expired-on-commit → illegal lazy-load), so Whoop workouts
# NEVER synced (recovery/sleep worked, activities didn't). The fix
# (fix-whoop-workout-sync.patch) is applied on the VM and baked into the running
# Docker image — it survives container restarts and VM reboots. It is ONLY lost
# if the VM is re-provisioned / OW is rebuilt from clean git source. This script
# re-applies it in that case. It lives in OUR repo on purpose — it does NOT touch
# Open Wearables' upstream git, so there's nothing to wait on.
#
# Idempotent: if the fix is already present it does nothing.
#
# Usage (run from your Mac; needs gcloud + SSH access to the VM):
#   bash infra/ow-patches/apply.sh
set -euo pipefail

ZONE="us-central1-a"
PROJECT="gen-lang-client-0009721575"
VM="open-wearables"
OW_DIR="~/open-wearables"

echo "Copying patch to the VM..."
gcloud compute scp "$(dirname "$0")/fix-whoop-workout-sync.patch" \
  "${VM}:/tmp/ow_fix.patch" --zone "$ZONE" --project "$PROJECT"

echo "Applying (idempotent) + rebuilding + restarting sync containers..."
gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT" --command '
  set -e
  cd ~/open-wearables
  if grep -q "expire_on_commit=False" backend/app/database.py; then
    echo "Fix already present — skipping patch."
  else
    git apply /tmp/ow_fix.patch && echo "Patch applied."
  fi
  echo "Rebuilding backend image..."
  docker build -t open-wearables-platform:latest ./backend >/dev/null
  echo "Recreating app + celery containers..."
  docker compose -f docker-compose.yml up -d --no-deps --no-build app celery-worker celery-beat
  echo "Done. Verifying:"
  docker exec celery-worker__open-wearables grep -c "expire_on_commit=False" /root_project/app/database.py
'
echo "OK — Whoop workout sync fix is in place."
