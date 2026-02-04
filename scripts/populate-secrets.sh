#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Populate v2 secrets from v1 and user input
# =====================================================
# This script copies known credentials from v1 and
# prompts for any missing ones.
#
# Usage: ./scripts/populate-secrets.sh
# =====================================================

V1_DIR="/Users/admin/openclaw"
SECRETS_DIR="/Users/admin/openclaw-002/secrets"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()  { echo -e "${GREEN}  ✓${NC} $*"; }
need(){ echo -e "${YELLOW}  ⬚${NC} $*"; }
skip(){ echo -e "  -  $* (not required for initial deploy)"; }

echo ""
echo "=========================================="
echo "  OpenClaw v2 Secret Population"
echo "=========================================="
echo ""

# --- Auto-migrate from v1 ---
echo "Checking v1 for reusable credentials..."

# Slack bot token
V1_SLACK=$(grep '^SLACK_BOT_TOKEN=' "${V1_DIR}/projects/mission-control/.env" 2>/dev/null | cut -d= -f2-)
if [ -n "${V1_SLACK}" ] && [ "${V1_SLACK}" != "CHANGE_ME_slack_bot_token" ]; then
    echo "${V1_SLACK}" > "${SECRETS_DIR}/slack_bot_token.txt"
    ok "slack_bot_token.txt — copied from v1"
else
    need "slack_bot_token.txt — needs manual entry"
fi

echo ""
echo "--- Remaining secrets checklist ---"
echo ""

check_secret() {
    local file="$1"
    local desc="$2"
    local required="$3"
    local current
    current=$(cat "${SECRETS_DIR}/${file}" 2>/dev/null || echo "")

    if echo "${current}" | grep -q "^CHANGE_ME"; then
        if [ "${required}" = "required" ]; then
            need "${file} — ${desc}"
        else
            skip "${file} — ${desc}"
        fi
    else
        ok "${file} — already set"
    fi
}

check_secret "anthropic_key.txt"    "Anthropic API key or Max OAuth token (routed via anthropic-max-router)" "required"
check_secret "db_password.txt"      "PostgreSQL password (change from placeholder)" "required"
check_secret "telegram_token.txt"   "Telegram bot token" "required"
check_secret "slack_bot_token.txt"  "Slack bot token" "required"
check_secret "slack_app_token.txt"  "Slack app-level token (Socket Mode)" "required"
check_secret "deepseek_key.txt"     "DeepSeek API key (powers 9 bulk agents — free 5M token trial)" "required"
check_secret "discord_token.txt"    "Discord bot token (Agent Command Center)" "required"
check_secret "cf_tunnel_token.txt"  "Cloudflare Tunnel token" "required"
check_secret "xai_key.txt"          "xAI Grok API key (2M context, $25 free credits)" "required"
check_secret "groq_key.txt"         "Groq API key (fast inference, free tier)" "optional"
check_secret "openrouter_key.txt"   "OpenRouter API key (400+ models, fallback routing)" "optional"
check_secret "openai_key.txt"       "OpenAI API key (GPT-4o, embeddings, vision)" "optional"
check_secret "alpaca_key.txt"       "Alpaca trading API key" "optional"
check_secret "alpaca_secret.txt"    "Alpaca trading API secret" "optional"
check_secret "airtable_key.txt"     "Airtable API key" "optional"
check_secret "retreaver_key.txt"    "Retreaver call tracking key" "optional"
check_secret "grafana_password.txt" "Grafana admin password" "optional"
check_secret "backup_passphrase.txt" "Backup encryption passphrase" "optional"

echo ""
echo "=========================================="
echo "  RECOMMENDED: Use 1Password"
echo "=========================================="
echo ""
echo "Instead of managing secret files manually, use 1Password:"
echo ""
echo "  1. Create a service account at https://my.1password.com/developer-tools/directory"
echo "  2. Create vault 'OpenClaw' with items matching scripts/op-secrets.sh mapping"
echo "  3. export OP_SERVICE_ACCOUNT_TOKEN='ops_...'"
echo "  4. ./scripts/op-secrets.sh pull"
echo ""
echo "This pulls all secrets from 1Password headlessly (no Touch ID),"
echo "writes them to secrets/ with 600 permissions, and verifies completeness."
echo ""
echo "Manual alternative:"
echo "  echo 'your-secret-value' > secrets/<filename>.txt"
echo ""
