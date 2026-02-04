#!/usr/bin/env bash
set -euo pipefail

# Setup Tailscale VPN link between Mac Mini and Hetzner VPS
# Usage: ./setup-tailscale.sh <hostname>
# Example: ./setup-tailscale.sh openclaw-mini
#          ./setup-tailscale.sh openclaw-vps

HOSTNAME="${1:?Usage: $0 <hostname> (e.g., openclaw-mini or openclaw-vps)}"

echo "=== Setting up Tailscale with hostname: ${HOSTNAME} ==="

# Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "Tailscale installed."
else
    echo "Tailscale already installed: $(tailscale version)"
fi

# Enable and start tailscaled service
if command -v systemctl &> /dev/null; then
    sudo systemctl enable --now tailscaled
fi

# Bring Tailscale up with hostname
echo "Connecting to Tailscale network..."
sudo tailscale up --hostname "${HOSTNAME}"

echo "=== Tailscale setup complete ==="
echo "Hostname: ${HOSTNAME}"
tailscale status
