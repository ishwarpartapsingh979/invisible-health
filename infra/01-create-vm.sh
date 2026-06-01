#!/usr/bin/env bash
# Create the GCE VM + firewall rule for Open Wearables.
# Idempotent: re-running is safe (will skip resources that already exist).

set -euo pipefail

PROJECT="${OW_PROJECT:-gen-lang-client-0009721575}"
ZONE="${OW_ZONE:-us-central1-a}"
VM_NAME="${OW_VM_NAME:-open-wearables}"
MACHINE_TYPE="${OW_MACHINE_TYPE:-e2-small}"
DISK_SIZE="${OW_DISK_SIZE:-30GB}"
FIREWALL_NAME="${OW_FIREWALL:-ow-allow-web}"
TAG="ow-server"

echo "▶ Project: $PROJECT  Zone: $ZONE  VM: $VM_NAME ($MACHINE_TYPE)"

# 1. Enable Compute Engine API (no-op if already enabled)
echo "▶ Ensuring Compute Engine API is enabled..."
gcloud services enable compute.googleapis.com --project="$PROJECT" >/dev/null

# 2. Create the VM (skip if exists)
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "✓ VM '$VM_NAME' already exists, skipping."
else
  echo "▶ Creating VM '$VM_NAME'..."
  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size="$DISK_SIZE" \
    --boot-disk-type=pd-balanced \
    --tags="$TAG"
fi

# 3. Create firewall rule (skip if exists)
if gcloud compute firewall-rules describe "$FIREWALL_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "✓ Firewall rule '$FIREWALL_NAME' already exists, skipping."
else
  echo "▶ Creating firewall rule '$FIREWALL_NAME'..."
  gcloud compute firewall-rules create "$FIREWALL_NAME" \
    --project="$PROJECT" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80,tcp:443,tcp:8000 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$TAG"
fi

# 4. Show external IP and what it maps to
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --project="$PROJECT" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
DASHED_IP="${EXTERNAL_IP//./-}"
HOSTNAME="${DASHED_IP}.nip.io"

echo ""
echo "✅ VM ready"
echo "   External IP:  $EXTERNAL_IP"
echo "   Hostname:     $HOSTNAME  (nip.io maps this to the IP for free)"
echo "   Final URL:    https://$HOSTNAME"
echo ""
echo "Next:  ./02-provision-vm.sh"
