#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Harden Hetzner VPS — run as root
# =====================================================

echo "=== Server Hardening ==="

# 1. System updates
echo "--- Updating system ---"
apt-get update -qq && apt-get upgrade -y -qq

# 2. Create deploy user
echo "--- Creating deploy user ---"
if ! id openclaw &>/dev/null; then
    useradd -m -s /bin/bash -G sudo openclaw
    mkdir -p /home/openclaw/.ssh
    cp /root/.ssh/authorized_keys /home/openclaw/.ssh/
    chown -R openclaw:openclaw /home/openclaw/.ssh
    chmod 700 /home/openclaw/.ssh
    chmod 600 /home/openclaw/.ssh/authorized_keys
    # Passwordless sudo for deploy user
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw
    echo "  ✓ Created user: openclaw"
else
    echo "  ✓ User openclaw already exists"
fi

# 3. SSH hardening
echo "--- Hardening SSH ---"
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak"

# Disable root login, password auth
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "${SSHD_CONFIG}"
sed -i 's/^#*UsePAM.*/UsePAM no/' "${SSHD_CONFIG}"

# Add rate limiting
if ! grep -q "MaxAuthTries" "${SSHD_CONFIG}"; then
    echo "MaxAuthTries 3" >> "${SSHD_CONFIG}"
fi

systemctl restart sshd
echo "  ✓ SSH hardened (key-only, no root login)"

# 4. Firewall (UFW)
echo "--- Configuring firewall ---"
apt-get install -y -qq ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
# Tailscale will handle internal traffic
# No need to expose Docker ports — Cloudflare Tunnel handles ingress
ufw --force enable
echo "  ✓ Firewall enabled (SSH only)"

# 5. Fail2ban
echo "--- Installing fail2ban ---"
apt-get install -y -qq fail2ban
cat > /etc/fail2ban/jail.local << 'F2B'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
F2B
systemctl enable fail2ban
systemctl restart fail2ban
echo "  ✓ Fail2ban configured (3 tries, 1h ban)"

# 6. Automatic security updates
echo "--- Enabling auto security updates ---"
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
echo "  ✓ Automatic security updates enabled"

# 7. Swap (useful for 4GB RAM)
echo "--- Creating swap ---"
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "  ✓ 2GB swap created"
else
    echo "  ✓ Swap already exists"
fi

echo ""
echo "=== Hardening complete ==="
echo "  - Root login: disabled"
echo "  - Password auth: disabled"
echo "  - Firewall: SSH only (port 22)"
echo "  - Fail2ban: 3 tries, 1h ban"
echo "  - Auto updates: enabled"
echo "  - Swap: 2GB"
echo ""
echo "IMPORTANT: Test SSH as 'openclaw' user before closing this session:"
echo "  ssh openclaw@$(hostname -I | awk '{print $1}')"
echo ""
