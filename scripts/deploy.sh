#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — Initial VPS deployment for OpenClaw v2.
# Installs Docker, creates openclaw user, generates secrets, starts all services.
# Run as root on a fresh Ubuntu 22.04 VPS.

INSTALL_DIR="/opt/openclaw"
OPENCLAW_USER="openclaw"

echo "=== OpenClaw v2 — Initial Deployment ==="

# --- Preflight check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# --- Install Docker if not present ---
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  echo "Docker installed successfully."
else
  echo "Docker already installed: $(docker --version)"
fi

# --- Create openclaw user ---
if ! id "$OPENCLAW_USER" &>/dev/null; then
  echo "Creating user: $OPENCLAW_USER"
  useradd --system --create-home --shell /bin/bash "$OPENCLAW_USER"
else
  echo "User $OPENCLAW_USER already exists."
fi

# Add to docker group
usermod -aG docker "$OPENCLAW_USER"
echo "User $OPENCLAW_USER added to docker group."

# --- Set up project directory ---
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Creating $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"
fi

# Copy project files if running from a different directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$PROJECT_DIR" != "$INSTALL_DIR" ]; then
  echo "Copying project files to $INSTALL_DIR..."
  cp -r "$PROJECT_DIR"/* "$INSTALL_DIR"/
  cp -r "$PROJECT_DIR"/.env "$INSTALL_DIR"/ 2>/dev/null || true
fi

# Create required directories
mkdir -p "$INSTALL_DIR/backups"
mkdir -p "$INSTALL_DIR/logs"

# --- Generate secrets if needed ---
if [ -x "$INSTALL_DIR/scripts/generate-secrets.sh" ]; then
  echo "Generating secrets..."
  bash "$INSTALL_DIR/scripts/generate-secrets.sh" "$INSTALL_DIR/secrets"
fi

# --- Set ownership ---
chown -R "$OPENCLAW_USER":"$OPENCLAW_USER" "$INSTALL_DIR"
chmod 600 "$INSTALL_DIR/secrets"/*.txt 2>/dev/null || true

# --- Start services ---
echo "Starting OpenClaw services..."
cd "$INSTALL_DIR"
docker compose up -d

echo ""
echo "=== Deployment complete ==="
echo "Services starting. Check status with:"
echo "  docker compose ps"
echo "  docker compose logs --tail 20"
echo ""
echo "Next steps:"
echo "  1. Update secrets in $INSTALL_DIR/secrets/ with real API keys"
echo "  2. Run scripts/setup-firewall.sh to configure UFW"
echo "  3. Run scripts/setup-fail2ban.sh to configure fail2ban"
echo "  4. Configure Cloudflare Tunnel (see config/cloudflared-setup.md)"
