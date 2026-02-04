#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Install Docker + Tailscale — run as root or sudo
# =====================================================

echo "=== Installing Docker + Tailscale ==="

# 1. Docker
echo "--- Installing Docker ---"
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker openclaw
    systemctl enable docker
    systemctl start docker
    echo "  ✓ Docker installed"
else
    echo "  ✓ Docker already installed"
fi

# Docker Compose plugin (already included with modern Docker)
docker compose version && echo "  ✓ Docker Compose available" || {
    apt-get install -y -qq docker-compose-plugin
    echo "  ✓ Docker Compose plugin installed"
}

# 2. Tailscale
echo "--- Installing Tailscale ---"
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "  ✓ Tailscale installed"
else
    echo "  ✓ Tailscale already installed"
fi

echo ""
echo "--- Tailscale auth ---"
echo "Run: sudo tailscale up --hostname=openclaw-v2"
echo "Then authenticate in browser."
echo ""

# 3. Allow Tailscale through firewall
echo "--- Configuring firewall for Tailscale ---"
ufw allow in on tailscale0 comment 'Tailscale'
echo "  ✓ Firewall allows Tailscale traffic"

# 4. Create app directory
echo "--- Setting up app directory ---"
mkdir -p /opt/openclaw
chown openclaw:openclaw /opt/openclaw
echo "  ✓ /opt/openclaw ready"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Authenticate Tailscale: sudo tailscale up --hostname=openclaw-v2"
echo "  2. Clone repo to /opt/openclaw"
echo "  3. Copy secrets: scp -r secrets/ openclaw@<server>:/opt/openclaw/secrets/"
echo "  4. Deploy: cd /opt/openclaw && docker compose up -d"
echo ""
