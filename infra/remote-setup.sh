#!/usr/bin/env bash
# Runs ON the VM (not locally). Called by 02-provision-vm.sh via gcloud ssh.
# Argument: $1 = public hostname (e.g. 34-66-12-34.nip.io)

set -euo pipefail

HOSTNAME="${1:?hostname required (e.g. 34-66-12-34.nip.io)}"
OW_DIR="$HOME/open-wearables"
ENV_SRC="/tmp/ow.env"

echo "▶ Updating apt..."
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release git debian-keyring debian-archive-keyring apt-transport-https

# --- Docker Engine + Compose plugin ---
if ! command -v docker >/dev/null 2>&1; then
  echo "▶ Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
else
  echo "✓ Docker already installed."
fi

# --- Open Wearables repo ---
if [[ ! -d "$OW_DIR" ]]; then
  echo "▶ Cloning Open Wearables..."
  git clone https://github.com/the-momentum/open-wearables.git "$OW_DIR"
else
  echo "✓ OW repo already cloned, pulling latest..."
  (cd "$OW_DIR" && git pull --ff-only)
fi

# Move uploaded .env into place
echo "▶ Installing .env..."
mkdir -p "$OW_DIR/backend/config"
cp "$ENV_SRC" "$OW_DIR/backend/config/.env"
chmod 600 "$OW_DIR/backend/config/.env"

# Frontend .env (use sample as-is — frontend isn't exposed publicly)
if [[ ! -f "$OW_DIR/frontend/.env" && -f "$OW_DIR/frontend/.env.example" ]]; then
  cp "$OW_DIR/frontend/.env.example" "$OW_DIR/frontend/.env"
fi

# --- Start the stack ---
echo "▶ Starting OW docker compose..."
cd "$OW_DIR"
sudo docker compose up -d

# --- Caddy reverse proxy with auto-HTTPS ---
if ! command -v caddy >/dev/null 2>&1; then
  echo "▶ Installing Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy
else
  echo "✓ Caddy already installed."
fi

echo "▶ Writing Caddyfile for $HOSTNAME..."
sudo tee /etc/caddy/Caddyfile >/dev/null <<EOF
${HOSTNAME} {
    reverse_proxy localhost:8000
}
EOF
sudo systemctl restart caddy

echo ""
echo "✅ VM provisioning done. OW reachable at https://$HOSTNAME"
echo "   (first request may take ~30s while Caddy fetches the TLS cert)"
