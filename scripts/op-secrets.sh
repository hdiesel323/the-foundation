#!/usr/bin/env bash
# ============================================================
# 1Password Secrets Manager for OpenClaw
# ============================================================
# Uses 1Password CLI (op) with a service account to pull secrets
# from a dedicated vault. No credentials on disk, no Touch ID needed.
#
# Prerequisites:
#   - 1Password CLI installed: brew install 1password-cli
#   - Service account token set: export OP_SERVICE_ACCOUNT_TOKEN="..."
#   - Vault "OpenClaw" (or custom name) created with secrets
#
# Usage:
#   ./scripts/op-secrets.sh pull          # Pull all secrets to secrets/ dir
#   ./scripts/op-secrets.sh pull --dry    # Show what would be pulled
#   ./scripts/op-secrets.sh verify        # Verify all secrets are present in 1Password
#   ./scripts/op-secrets.sh env           # Output as env vars (for op run / docker)
#   ./scripts/op-secrets.sh rotate <key>  # Rotate a specific secret
#   ./scripts/op-secrets.sh clean         # Remove all local secret files
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_DIR/secrets"
CONFIG_FILE="$PROJECT_DIR/config/op-secrets.json"

# 1Password vault name (override with OP_VAULT env var)
VAULT="${OP_VAULT:-OpenClaw}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Secret mapping: local filename -> 1Password item/field
# ============================================================
# Format: "local_file:op_item:op_field"
# op_field defaults to "password" if not specified
SECRETS=(
  "db_password.txt:OpenClaw Database:password"
  "anthropic_key.txt:Anthropic API:api_key"
  "openai_key.txt:OpenAI API:api_key"
  "slack_bot_token.txt:Slack Bot:bot_token"
  "slack_app_token.txt:Slack Bot:app_token"
  "telegram_token.txt:Telegram Bot:bot_token"
  "discord_token.txt:Discord Bot:bot_token"
  "cf_tunnel_token.txt:Cloudflare Tunnel:tunnel_token"
  "grafana_password.txt:Grafana:admin_password"
  "backup_passphrase.txt:Backup Encryption:passphrase"
  "deepseek_key.txt:DeepSeek API:api_key"
  "xai_key.txt:xAI Grok API:api_key"
  "groq_key.txt:Groq API:api_key"
  "openrouter_key.txt:OpenRouter API:api_key"
  "alpaca_key.txt:Alpaca Trading:api_key"
  "alpaca_secret.txt:Alpaca Trading:api_secret"
  "retreaver_key.txt:Retreaver API:api_key"
  "airtable_key.txt:Airtable API:api_key"
)

# ============================================================
# Preflight checks
# ============================================================
check_op() {
  if ! command -v op &>/dev/null; then
    echo -e "${RED}Error: 1Password CLI (op) not installed${NC}"
    echo "Install: brew install 1password-cli"
    exit 1
  fi

  if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    echo -e "${RED}Error: OP_SERVICE_ACCOUNT_TOKEN not set${NC}"
    echo "Create a service account at: https://my.1password.com/developer-tools/directory"
    echo "Then: export OP_SERVICE_ACCOUNT_TOKEN='ops_...'"
    exit 1
  fi

  # Verify we can authenticate
  if ! op vault list --format=json &>/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot authenticate with 1Password${NC}"
    echo "Check your OP_SERVICE_ACCOUNT_TOKEN"
    exit 1
  fi

  # Verify vault exists
  if ! op vault get "$VAULT" --format=json &>/dev/null 2>&1; then
    echo -e "${RED}Error: Vault '$VAULT' not found${NC}"
    echo "Available vaults:"
    op vault list --format=json | python3 -c "import sys,json; [print(f'  - {v[\"name\"]}') for v in json.load(sys.stdin)]"
    exit 1
  fi

  echo -e "${GREEN}1Password authenticated | Vault: $VAULT${NC}"
}

# ============================================================
# Pull secrets from 1Password to local files
# ============================================================
cmd_pull() {
  local dry_run=false
  if [ "${1:-}" = "--dry" ]; then
    dry_run=true
    echo -e "${YELLOW}DRY RUN — no files will be written${NC}"
  fi

  check_op
  mkdir -p "$SECRETS_DIR"

  local pulled=0
  local failed=0
  local skipped=0

  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file op_item op_field <<< "$mapping"

    echo -n "  $local_file <- $op_item/$op_field ... "

    # Try to read from 1Password
    local value
    if value=$(op item get "$op_item" --vault "$VAULT" --fields "$op_field" 2>/dev/null); then
      if [ -z "$value" ]; then
        echo -e "${YELLOW}EMPTY (skipped)${NC}"
        ((skipped++))
        continue
      fi

      if $dry_run; then
        echo -e "${BLUE}OK (would write ${#value} chars)${NC}"
      else
        echo -n "$value" > "$SECRETS_DIR/$local_file"
        chmod 600 "$SECRETS_DIR/$local_file"
        echo -e "${GREEN}OK (${#value} chars)${NC}"
      fi
      ((pulled++))
    else
      echo -e "${RED}NOT FOUND${NC}"
      ((failed++))
    fi
  done

  echo ""
  echo -e "Results: ${GREEN}$pulled pulled${NC} | ${RED}$failed missing${NC} | ${YELLOW}$skipped empty${NC}"

  if [ $failed -gt 0 ]; then
    echo -e "\n${YELLOW}Missing items need to be created in 1Password vault '$VAULT'${NC}"
    echo "Use: op item create --vault '$VAULT' --category 'API Credential' --title 'Item Name'"
  fi
}

# ============================================================
# Verify all secrets exist in 1Password
# ============================================================
cmd_verify() {
  check_op

  local found=0
  local missing=0

  echo -e "\nChecking ${#SECRETS[@]} secrets in vault '$VAULT':\n"

  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file op_item op_field <<< "$mapping"

    echo -n "  $op_item / $op_field ... "

    if op item get "$op_item" --vault "$VAULT" --fields "$op_field" &>/dev/null 2>&1; then
      echo -e "${GREEN}OK${NC}"
      ((found++))
    else
      echo -e "${RED}MISSING${NC}"
      ((missing++))
    fi
  done

  echo ""
  echo -e "Results: ${GREEN}$found found${NC} | ${RED}$missing missing${NC} / ${#SECRETS[@]} total"

  # Also check local files
  echo -e "\nLocal files in secrets/:"
  local local_ok=0
  local local_placeholder=0
  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file op_item op_field <<< "$mapping"
    local filepath="$SECRETS_DIR/$local_file"

    if [ -f "$filepath" ]; then
      local content
      content=$(cat "$filepath")
      if [[ "$content" == *"CHANGE_ME"* ]]; then
        echo -e "  $local_file: ${YELLOW}PLACEHOLDER${NC}"
        ((local_placeholder++))
      else
        echo -e "  $local_file: ${GREEN}SET${NC}"
        ((local_ok++))
      fi
    else
      echo -e "  $local_file: ${RED}MISSING${NC}"
    fi
  done

  echo -e "\nLocal: ${GREEN}$local_ok set${NC} | ${YELLOW}$local_placeholder placeholder${NC}"
}

# ============================================================
# Output secrets as environment variables
# ============================================================
cmd_env() {
  check_op

  # Map secret files to env var names
  declare -A ENV_MAP=(
    ["db_password.txt"]="DB_PASSWORD"
    ["anthropic_key.txt"]="ANTHROPIC_API_KEY"
    ["openai_key.txt"]="OPENAI_API_KEY"
    ["slack_bot_token.txt"]="SLACK_BOT_TOKEN"
    ["slack_app_token.txt"]="SLACK_APP_TOKEN"
    ["telegram_token.txt"]="TELEGRAM_BOT_TOKEN"
    ["discord_token.txt"]="DISCORD_BOT_TOKEN"
    ["cf_tunnel_token.txt"]="CF_TUNNEL_TOKEN"
    ["grafana_password.txt"]="GF_SECURITY_ADMIN_PASSWORD"
    ["backup_passphrase.txt"]="BACKUP_PASSPHRASE"
    ["deepseek_key.txt"]="DEEPSEEK_API_KEY"
    ["xai_key.txt"]="XAI_API_KEY"
    ["groq_key.txt"]="GROQ_API_KEY"
    ["openrouter_key.txt"]="OPENROUTER_API_KEY"
    ["alpaca_key.txt"]="ALPACA_API_KEY"
    ["alpaca_secret.txt"]="ALPACA_API_SECRET"
    ["retreaver_key.txt"]="RETREAVER_API_KEY"
    ["airtable_key.txt"]="AIRTABLE_API_KEY"
  )

  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file op_item op_field <<< "$mapping"

    local env_var="${ENV_MAP[$local_file]:-}"
    if [ -z "$env_var" ]; then
      continue
    fi

    local value
    if value=$(op item get "$op_item" --vault "$VAULT" --fields "$op_field" 2>/dev/null); then
      if [ -n "$value" ]; then
        echo "export ${env_var}=\"${value}\""
      fi
    fi
  done
}

# ============================================================
# Rotate a specific secret
# ============================================================
cmd_rotate() {
  local key_name="${1:-}"
  if [ -z "$key_name" ]; then
    echo "Usage: $0 rotate <secret_file_name>"
    echo "Example: $0 rotate db_password.txt"
    exit 1
  fi

  check_op

  # Find the mapping
  local found=false
  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file op_item op_field <<< "$mapping"
    if [ "$local_file" = "$key_name" ]; then
      found=true

      echo -e "Rotating: ${BLUE}$op_item / $op_field${NC}"

      # Generate new value
      local new_value
      new_value=$(op item get "$op_item" --vault "$VAULT" --fields "$op_field" 2>/dev/null || echo "")

      if [ -z "$new_value" ]; then
        echo -e "${RED}Cannot read current value from 1Password${NC}"
        exit 1
      fi

      echo "Current value length: ${#new_value} chars"
      echo -e "${YELLOW}To rotate: update the value in 1Password, then run 'pull'${NC}"
      echo "  op item edit '$op_item' --vault '$VAULT' '$op_field=NEW_VALUE'"
      echo "  $0 pull"
      break
    fi
  done

  if ! $found; then
    echo -e "${RED}Unknown secret: $key_name${NC}"
    echo "Available:"
    for mapping in "${SECRETS[@]}"; do
      IFS=':' read -r local_file _ _ <<< "$mapping"
      echo "  - $local_file"
    done
  fi
}

# ============================================================
# Clean local secret files
# ============================================================
cmd_clean() {
  echo -e "${YELLOW}Removing all secret files from $SECRETS_DIR${NC}"

  local removed=0
  for mapping in "${SECRETS[@]}"; do
    IFS=':' read -r local_file _ _ <<< "$mapping"
    local filepath="$SECRETS_DIR/$local_file"
    if [ -f "$filepath" ]; then
      rm -f "$filepath"
      echo "  Removed: $local_file"
      ((removed++))
    fi
  done

  echo -e "${GREEN}Removed $removed secret files${NC}"
  echo "Run '$0 pull' to re-fetch from 1Password"
}

# ============================================================
# Main
# ============================================================
case "${1:-help}" in
  pull)
    cmd_pull "${2:-}"
    ;;
  verify)
    cmd_verify
    ;;
  env)
    cmd_env
    ;;
  rotate)
    cmd_rotate "${2:-}"
    ;;
  clean)
    cmd_clean
    ;;
  help|*)
    echo "OpenClaw 1Password Secrets Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  pull [--dry]    Pull secrets from 1Password to secrets/ directory"
    echo "  verify          Check which secrets exist in 1Password vs locally"
    echo "  env             Output secrets as export statements (for eval)"
    echo "  rotate <key>    Show instructions for rotating a secret"
    echo "  clean           Remove all local secret files"
    echo ""
    echo "Environment:"
    echo "  OP_SERVICE_ACCOUNT_TOKEN  1Password service account token (required)"
    echo "  OP_VAULT                  Vault name (default: OpenClaw)"
    echo ""
    echo "Setup:"
    echo "  1. Install 1Password CLI: brew install 1password-cli"
    echo "  2. Create service account: https://my.1password.com/developer-tools/directory"
    echo "  3. Create vault 'OpenClaw' and add items with fields listed below"
    echo "  4. export OP_SERVICE_ACCOUNT_TOKEN='ops_...'"
    echo "  5. $0 pull"
    echo ""
    echo "Required 1Password items (vault: $VAULT):"
    echo ""
    printf "  %-25s %-15s %s\n" "ITEM" "FIELD" "LOCAL FILE"
    printf "  %-25s %-15s %s\n" "-------------------------" "---------------" "-------------------"
    for mapping in "${SECRETS[@]}"; do
      IFS=':' read -r local_file op_item op_field <<< "$mapping"
      printf "  %-25s %-15s %s\n" "$op_item" "$op_field" "$local_file"
    done
    ;;
esac
