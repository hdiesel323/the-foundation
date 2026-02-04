#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Create Hetzner VPS for OpenClaw v2
# =====================================================
# Prerequisites: hcloud CLI installed, API token set
#
# Usage:
#   export HCLOUD_TOKEN="your-token-here"
#   ./scripts/vps/01-create-server.sh
# =====================================================

SERVER_NAME="${SERVER_NAME:-openclaw-v2}"
SERVER_TYPE="${SERVER_TYPE:-cpx21}"   # 3 vCPU, 4GB RAM, 80GB — €7.50/mo
LOCATION="${LOCATION:-hel1}"          # Helsinki
IMAGE="${IMAGE:-ubuntu-22.04}"
SSH_KEY_NAME="${SSH_KEY_NAME:-openclaw-deploy}"

echo "=== Creating Hetzner VPS ==="
echo "  Name:     ${SERVER_NAME}"
echo "  Type:     ${SERVER_TYPE} (3 vCPU / 4GB / 80GB)"
echo "  Location: ${LOCATION} (Helsinki)"
echo "  Image:    ${IMAGE}"
echo ""

# Check token
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo "ERROR: HCLOUD_TOKEN not set."
    echo "  1. Go to https://console.hetzner.cloud/projects"
    echo "  2. Select your project → Security → API Tokens"
    echo "  3. Generate a Read & Write token"
    echo "  4. export HCLOUD_TOKEN='your-token'"
    exit 1
fi

# Upload SSH key if not already there
if ! hcloud ssh-key describe "${SSH_KEY_NAME}" &>/dev/null; then
    echo "Uploading SSH key..."
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        hcloud ssh-key create --name "${SSH_KEY_NAME}" --public-key-from-file ~/.ssh/id_ed25519.pub
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        hcloud ssh-key create --name "${SSH_KEY_NAME}" --public-key-from-file ~/.ssh/id_rsa.pub
    else
        echo "ERROR: No SSH public key found (~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"
        echo "Generate one: ssh-keygen -t ed25519 -C 'openclaw-deploy'"
        exit 1
    fi
    echo "  ✓ SSH key uploaded: ${SSH_KEY_NAME}"
else
    echo "  ✓ SSH key already exists: ${SSH_KEY_NAME}"
fi

# Create server
echo ""
echo "Creating server..."
hcloud server create \
    --name "${SERVER_NAME}" \
    --type "${SERVER_TYPE}" \
    --location "${LOCATION}" \
    --image "${IMAGE}" \
    --ssh-key "${SSH_KEY_NAME}" \
    --label env=production \
    --label project=openclaw

echo ""
echo "  ✓ Server created!"
echo ""

# Get IP
SERVER_IP=$(hcloud server ip "${SERVER_NAME}")
echo "  Server IP: ${SERVER_IP}"
echo ""
echo "Next steps:"
echo "  1. SSH in: ssh root@${SERVER_IP}"
echo "  2. Run hardening: scp scripts/vps/02-harden.sh root@${SERVER_IP}:/tmp/ && ssh root@${SERVER_IP} bash /tmp/02-harden.sh"
echo "  3. Install Docker: ssh root@${SERVER_IP} bash /tmp/03-install-docker.sh"
echo ""
