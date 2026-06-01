#!/usr/bin/env bash
# Point iOS and the Whoop developer dashboard at the new VM URL.
# - Updates OpenWearablesConfig.swift baseURL in place (DEBUG branch).
# - Prints the exact Whoop redirect URL to paste into the dev dashboard.

set -euo pipefail

PROJECT="${OW_PROJECT:-gen-lang-client-0009721575}"
ZONE="${OW_ZONE:-us-central1-a}"
VM_NAME="${OW_VM_NAME:-open-wearables}"
IOS_CONFIG="${OW_IOS_CONFIG:-$HOME/Documents/Invisible_Health/Invisible_Health/Invisible_Health/OpenWearables/OpenWearablesConfig.swift}"

echo "▶ Fetching VM external IP..."
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --project="$PROJECT" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
DASHED_IP="${EXTERNAL_IP//./-}"
HOSTNAME="${DASHED_IP}.nip.io"
BASE_URL="https://${HOSTNAME}/api/v1"
REDIRECT_URL="https://${HOSTNAME}/api/v1/oauth/whoop/callback"

if [[ ! -f "$IOS_CONFIG" ]]; then
  echo "❌ OpenWearablesConfig.swift not found at: $IOS_CONFIG"
  exit 1
fi

echo "▶ Updating iOS DEBUG baseURL → $BASE_URL"
# Replace any existing DEBUG baseURL (localhost OR previous ngrok/nip.io).
# Matches: static let baseURL = "<anything>/api/v1"
sed -i.bak -E "s|(static let baseURL = \")[^\"]*(\")|\1${BASE_URL}\2|" "$IOS_CONFIG"

# Show what changed (DEBUG branch only)
echo ""
grep -n -A1 '#if DEBUG' "$IOS_CONFIG" | head -6

echo ""
echo "✅ iOS config updated. Now manually:"
echo ""
echo "  1) Whoop developer dashboard → your app → Redirect URL:"
echo "       $REDIRECT_URL"
echo "     Click Update App."
echo ""
echo "  2) Smoke-test the new URL is alive:"
echo "       curl -s -o /dev/null -w '%{http_code}\\n' https://${HOSTNAME}/docs"
echo ""
echo "  3) Cmd+R in Xcode to rebuild iOS app with new baseURL."
echo ""
echo "  4) In the app: DEVICES tab → Disconnect → Connect Whoop (tokens were"
echo "     tied to the old redirect URI and need re-issuing)."
echo ""
echo "If you were running local ngrok, you can kill it now:"
echo "  pkill -f 'ngrok http 8000'  # safe to ignore 'no matching processes'"
