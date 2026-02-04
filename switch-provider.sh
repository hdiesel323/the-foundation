#!/bin/bash
#
# switch-provider.sh - Quick switch between Claude API providers
#
# MIT License
#
# Copyright (c) 2025
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Usage: ./switch-provider.sh [claude|zai|status]

set -e

PROVIDER="${1:-claude}"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# z.ai API key - set this once or pass as ZAI_API_KEY env variable
ZAI_API_KEY="${ZAI_API_KEY:-}"

# Ensure settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "❌ Error: Claude settings file not found at $SETTINGS_FILE"
  exit 1
fi

case "$PROVIDER" in
  claude|anthropic|official|max)
    echo "🔄 Switching to Claude MAX (Official Anthropic API)..."

    # Backup first
    BACKUP="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"

    # Remove ANTHROPIC_BASE_URL to use default Anthropic API
    # Keep OAuth token, remove any API key override
    tmp_file=$(mktemp)
    jq 'del(.env.ANTHROPIC_BASE_URL) | del(.env.ANTHROPIC_API_KEY)' "$SETTINGS_FILE" > "$tmp_file"
    mv "$tmp_file" "$SETTINGS_FILE"

    echo "✅ Now using: Claude MAX (Official Anthropic API)"
    echo "   Authentication: OAuth Token"
    echo "   Backup saved: $BACKUP"
    ;;

  zai|z.ai)
    echo "🔄 Switching to z.ai API..."

    # Check for z.ai API key
    if [ -z "$ZAI_API_KEY" ]; then
      echo "❌ Error: ZAI_API_KEY environment variable not set!"
      echo ""
      echo "Set it with:"
      echo "  export ZAI_API_KEY='your-zai-api-key'"
      echo ""
      echo "Or add to ~/.zshrc for persistence:"
      echo "  echo 'export ZAI_API_KEY=\"your-key\"' >> ~/.zshrc"
      echo "  source ~/.zshrc"
      exit 1
    fi

    # Backup first
    BACKUP="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"

    # Set ANTHROPIC_BASE_URL for z.ai and use API key instead of OAuth
    tmp_file=$(mktemp)
    jq --arg key "$ZAI_API_KEY" '
      .env.ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic" |
      .env.ANTHROPIC_API_KEY = $key
    ' "$SETTINGS_FILE" > "$tmp_file"
    mv "$tmp_file" "$SETTINGS_FILE"

    echo "✅ Now using: z.ai API (GLM Coding Plan)"
    echo "   Authentication: API Key (${ZAI_API_KEY:0:12}...)"
    echo "   Backup saved: $BACKUP"
    ;;

  status|current)
    echo "📊 Current Provider Configuration:"
    echo "─────────────────────────────────"

    if [ -f "$SETTINGS_FILE" ]; then
      auth_token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // "not set"' "$SETTINGS_FILE" 2>/dev/null)
      api_key=$(jq -r '.env.ANTHROPIC_API_KEY // "not set"' "$SETTINGS_FILE" 2>/dev/null)
      base_url=$(jq -r '.env.ANTHROPIC_BASE_URL // "default (Anthropic Official)"' "$SETTINGS_FILE" 2>/dev/null)

      echo "Base URL: $base_url"

      if [ "$api_key" != "not set" ] && [ -n "$api_key" ]; then
        echo "Authentication: API Key (${api_key:0:12}...)"
        echo ""
        echo "✅ Using: z.ai API"
      else
        echo "Authentication: OAuth Token (${auth_token:0:20}...)"
        echo ""
        if [ "$base_url" = "default (Anthropic Official)" ] || [ -z "$base_url" ]; then
          echo "✅ Using: Claude MAX (Official Anthropic)"
        else
          echo "✅ Using: $base_url"
        fi
      fi
    fi
    ;;

  *)
    echo "❌ Unknown provider: $PROVIDER"
    echo ""
    echo "Usage: $0 [claude|zai|status]"
    echo ""
    echo "Commands:"
    echo "  claude    - Switch to Claude MAX (Official Anthropic)"
    echo "  zai       - Switch to z.ai API"
    echo "  status    - Show current provider"
    echo ""
    echo "Environment Variables:"
    echo "  ZAI_API_KEY - Required for z.ai provider"
    echo ""
    exit 1
    ;;
esac
