#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Deploy OpenClaw v2 to VPS — run on VPS as openclaw user
# =====================================================

APP_DIR="/opt/openclaw"

echo "=== Deploying OpenClaw v2 ==="

cd "${APP_DIR}"

# 1. Pull latest
echo "--- Pulling latest code ---"
if [ -d .git ]; then
    git pull
else
    echo "ERROR: Not a git repo. Clone first:"
    echo "  git clone <repo-url> ${APP_DIR}"
    exit 1
fi

# 2. Pull secrets from 1Password (if configured)
if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    echo "--- Pulling secrets from 1Password ---"
    bash scripts/op-secrets.sh pull
else
    echo "--- Verifying local secrets ---"
    echo "  (Set OP_SERVICE_ACCOUNT_TOKEN to pull from 1Password instead)"
    MISSING=0
    for secret in anthropic_key db_password telegram_token slack_bot_token cf_tunnel_token; do
        if grep -q "^CHANGE_ME" "secrets/${secret}.txt" 2>/dev/null; then
            echo "  x secrets/${secret}.txt is still a placeholder!"
            MISSING=$((MISSING + 1))
        elif [ ! -f "secrets/${secret}.txt" ]; then
            echo "  x secrets/${secret}.txt missing!"
            MISSING=$((MISSING + 1))
        else
            echo "  ok secrets/${secret}.txt"
        fi
    done

    if [ "${MISSING}" -gt 0 ]; then
        echo ""
        echo "WARNING: ${MISSING} required secret(s) not set."
        echo "Services may fail to start. Continue anyway? (y/N)"
        read -r response
        if [ "${response}" != "y" ]; then
            exit 1
        fi
    fi
fi

# 3. Copy data (GraphMem DB, competitive intel, etc.)
echo "--- Syncing data ---"
if [ ! -f "mcp-servers/graphmem/clawd_brain.db" ]; then
    echo "  ⚠ GraphMem DB not found — run migration or copy from Mac"
fi

# 4. Build and start
echo "--- Starting services ---"
docker compose pull 2>/dev/null || true
docker compose build --no-cache
docker compose up -d

echo ""
echo "--- Checking health ---"
sleep 10
docker compose ps

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Services:"
echo "  PostgreSQL:  port 5434 (internal)"
echo "  Seldon API:  port 18789"
echo "  Grafana:     port 3000 (via Cloudflare Tunnel)"
echo ""
echo "Verify:"
echo "  curl http://localhost:18789/seldon/status"
echo "  docker compose logs -f seldon"
echo ""
