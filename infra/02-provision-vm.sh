#!/usr/bin/env bash
# Provision OW on the GCE VM:
#   - install Docker + Compose
#   - clone the Open Wearables repo
#   - copy your local .env up
#   - docker compose up -d
#   - install Caddy with a nip.io HTTPS cert in front of port 8000

set -euo pipefail

PROJECT="${OW_PROJECT:-gen-lang-client-0009721575}"
ZONE="${OW_ZONE:-us-central1-a}"
VM_NAME="${OW_VM_NAME:-open-wearables}"
LOCAL_ENV="${OW_LOCAL_ENV:-$HOME/Documents/Invisible_Health/open-wearables/backend/config/.env}"

if [[ ! -f "$LOCAL_ENV" ]]; then
  echo "❌ Local .env not found at: $LOCAL_ENV"
  echo "   Set OW_LOCAL_ENV=/path/to/.env or fix the default."
  exit 1
fi

echo "▶ Fetching VM external IP..."
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --project="$PROJECT" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
DASHED_IP="${EXTERNAL_IP//./-}"
HOSTNAME="${DASHED_IP}.nip.io"

echo "   IP:       $EXTERNAL_IP"
echo "   Hostname: $HOSTNAME"

# 1. Patch the local .env into a "for-the-VM" copy with the new
#    WHOOP_REDIRECT_URI + API_BASE_URL pointing at the public hostname.
TMP_ENV=$(mktemp)
trap 'rm -f "$TMP_ENV"' EXIT
sed -E \
  -e "s#^WHOOP_REDIRECT_URI=.*#WHOOP_REDIRECT_URI=https://${HOSTNAME}/api/v1/oauth/whoop/callback#" \
  -e "s#^API_BASE_URL=.*#API_BASE_URL=https://${HOSTNAME}#" \
  "$LOCAL_ENV" > "$TMP_ENV"

echo "▶ Copying patched .env to VM..."
gcloud compute scp "$TMP_ENV" "${VM_NAME}:/tmp/ow.env" --zone="$ZONE" --project="$PROJECT" --quiet

REMOTE_SCRIPT="$(dirname "$0")/remote-setup.sh"
echo "▶ Copying remote-setup.sh to VM..."
gcloud compute scp "$REMOTE_SCRIPT" "${VM_NAME}:/tmp/remote-setup.sh" --zone="$ZONE" --project="$PROJECT" --quiet

echo "▶ Running remote setup on VM (8–10 min, this is the slow part)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --quiet --command="bash /tmp/remote-setup.sh '$HOSTNAME'"

echo ""
echo "✅ Provisioning complete"
echo "   Public URL:  https://$HOSTNAME"
echo "   Test with:   curl -s -o /dev/null -w '%{http_code}\\n' https://$HOSTNAME/docs"
echo ""
echo "Next:  ./03-update-clients.sh"
