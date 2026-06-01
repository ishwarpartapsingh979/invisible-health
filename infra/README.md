# Open Wearables on Google Compute Engine

Scripts to deploy the Open Wearables backend (Docker stack) to a single GCE VM
with HTTPS via Caddy + nip.io. Solo-dev friendly: no domain to buy, no DNS to
manage, no manual TLS cert renewal.

## What gets created

- One `e2-small` VM in `us-central1-a` (`open-wearables`) — ~$13/mo after free trial
- One firewall rule (`ow-allow-web`) allowing 80, 443, 8000 from anywhere
- 30 GB pd-balanced boot disk
- Caddy reverse proxy with auto-renewing Let's Encrypt cert
- Final public URL pattern: `https://<dashed-ip>.nip.io` (e.g. `https://34-66-12-34.nip.io`)

## Prereqs (one-time)

- `gcloud` CLI authenticated as the owner of project `gen-lang-client-0009721575`
  (`gcloud auth login` if needed)
- Compute Engine API enabled (the first script does this for you)
- `~/Documents/Invisible_Health/open-wearables/backend/config/.env` exists with
  WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET, ADMIN_EMAIL, ADMIN_PASSWORD set

## Step-by-step

```bash
cd ~/Documents/Invisible_Health/Invisible_Health/infra

# 1. Create the VM + firewall (~3 min). Idempotent: safe to re-run.
./01-create-vm.sh

# 2. Provision OW + Caddy on the VM (~8 min). Pulls your local .env, scps it
#    over, runs remote-setup.sh on the VM.
./02-provision-vm.sh

# 3. Point iOS + Whoop dashboard at the new HTTPS URL.
./03-update-clients.sh
# Then manually update Whoop dev dashboard's redirect URL (script prints what to paste).
```

## After it's running

- **OW dev portal:** `https://<dashed-ip>.nip.io:3000` is not exposed by Caddy
  by default — the dev portal stays on the VM's internal network. SSH-tunnel
  to view: `gcloud compute ssh open-wearables -- -L 3000:localhost:3000`
- **Updating OW:** SSH in and `cd ~/open-wearables && git pull && docker compose up -d`
- **Tear it down:** `gcloud compute instances delete open-wearables --zone=us-central1-a`
  → billing stops immediately.
- **Switch back to local ngrok:** edit `OpenWearablesConfig.swift` baseURL
  back to the ngrok URL, re-update Whoop dashboard.

## Cost watch

- VM running 24/7 at e2-small: ~$13/mo
- 30 GB pd-balanced disk: ~$3/mo
- Egress: minimal for solo dogfooding
- Free trial covers first 90 days entirely
- Stop the VM (`gcloud compute instances stop open-wearables`) to drop compute
  charges; disk + IP still cost a few $/mo
