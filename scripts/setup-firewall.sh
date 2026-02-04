#!/usr/bin/env bash
set -euo pipefail

# OpenClaw v2 — UFW Firewall Setup
# Zero exposed ports. All HTTP access via Cloudflare Tunnel.
# Only SSH (port 22) is allowed inbound.

echo "=== OpenClaw Firewall Setup ==="

# Reset UFW to defaults (non-interactive)
ufw --force reset

# Default policies: deny all incoming, allow all outgoing
ufw default deny incoming
ufw default allow outgoing

# Allow SSH only
ufw allow 22/tcp

# Enable UFW (non-interactive)
ufw --force enable

echo "=== Firewall configured ==="
ufw status verbose
