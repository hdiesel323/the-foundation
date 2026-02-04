#!/usr/bin/env bash
set -euo pipefail

# generate-secrets.sh — Generate fresh credentials for OpenClaw deployment.
# Generates random passwords for db_password, grafana_password, backup_passphrase.
# API tokens (Anthropic, OpenAI, Slack, Telegram, Cloudflare) must be set manually.

SECRETS_DIR="${1:-secrets}"

mkdir -p "$SECRETS_DIR"

generate_password() {
  openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

echo "Generating secrets in $SECRETS_DIR/ ..."

# Generate random credentials for locally-controlled services
printf '%s' "$(generate_password)" > "$SECRETS_DIR/db_password.txt"
printf '%s' "$(generate_password)" > "$SECRETS_DIR/grafana_password.txt"
printf '%s' "$(generate_password)" > "$SECRETS_DIR/backup_passphrase.txt"

# Create placeholder files for API tokens that must be provided manually
for token_file in anthropic_key openai_key slack_bot_token slack_app_token telegram_token cf_tunnel_token; do
  target="$SECRETS_DIR/${token_file}.txt"
  if [ ! -f "$target" ] || grep -q '^CHANGE_ME' "$target" 2>/dev/null; then
    printf '%s' "CHANGE_ME_${token_file}" > "$target"
  fi
done

# Lock down permissions — owner read/write only
chmod 600 "$SECRETS_DIR"/*.txt

echo "Done. Generated:"
echo "  $SECRETS_DIR/db_password.txt       (random 32-char)"
echo "  $SECRETS_DIR/grafana_password.txt   (random 32-char)"
echo "  $SECRETS_DIR/backup_passphrase.txt  (random 32-char)"
echo ""
echo "Manual setup required:"
echo "  $SECRETS_DIR/anthropic_key.txt"
echo "  $SECRETS_DIR/openai_key.txt"
echo "  $SECRETS_DIR/slack_bot_token.txt"
echo "  $SECRETS_DIR/slack_app_token.txt"
echo "  $SECRETS_DIR/telegram_token.txt"
echo "  $SECRETS_DIR/cf_tunnel_token.txt"
