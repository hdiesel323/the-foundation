#!/usr/bin/env bash
set -euo pipefail

# OpenClaw v2 — fail2ban Setup for SSH Brute-Force Protection
# Matches openclaw_PRD.md Section 17 (fail2ban)

echo "=== OpenClaw fail2ban Setup ==="

# Install fail2ban if not present
if ! command -v fail2ban-server &>/dev/null; then
  echo "Installing fail2ban..."
  apt-get update -qq && apt-get install -y -qq fail2ban
fi

# Write jail.local configuration
cat > /etc/fail2ban/jail.local <<'EOF'
# /etc/fail2ban/jail.local
# OpenClaw v2 — SSH brute-force protection

[sshd]
enabled = true
maxretry = 3
bantime = 3600
findtime = 600
EOF

echo "Wrote /etc/fail2ban/jail.local"

# Enable and restart fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

echo "=== fail2ban configured ==="
fail2ban-client status sshd
