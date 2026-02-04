#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Setup Discord Server for OpenClaw Command Center
# =====================================================
# Creates categories and channels matching channels.json
#
# Prerequisites:
#   - Discord bot token with Manage Channels permission
#   - Bot invited to server with admin perms
#   - Guild (server) ID
#
# Usage:
#   DISCORD_BOT_TOKEN="your-token" DISCORD_GUILD_ID="your-guild-id" \
#     ./scripts/setup-discord.sh
# =====================================================

TOKEN="${DISCORD_BOT_TOKEN:?Set DISCORD_BOT_TOKEN}"
GUILD="${DISCORD_GUILD_ID:?Set DISCORD_GUILD_ID}"
API="https://discord.com/api/v10"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[discord]${NC} $*"; }
ok()  { echo -e "${GREEN}  ✓${NC} $*"; }

auth_header="Authorization: Bot ${TOKEN}"

# Create a category and return its ID
create_category() {
    local name="$1"
    local result
    result=$(curl -s -X POST "${API}/guilds/${GUILD}/channels" \
        -H "${auth_header}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${name}\", \"type\": 4}")
    echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# Create a text channel under a category
create_channel() {
    local name="$1"
    local category_id="$2"
    local topic="$3"
    curl -s -X POST "${API}/guilds/${GUILD}/channels" \
        -H "${auth_header}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${name}\", \"type\": 0, \"parent_id\": \"${category_id}\", \"topic\": \"${topic}\"}" > /dev/null
}

echo ""
echo "=========================================="
echo "  OpenClaw Discord Command Center Setup"
echo "=========================================="
echo ""

# COMMAND CENTER
log "Creating COMMAND CENTER category..."
cat_id=$(create_category "COMMAND CENTER")
if [ -n "${cat_id}" ]; then
    ok "Category created: COMMAND CENTER (${cat_id})"
    create_channel "mission-briefing" "${cat_id}" "Daily briefs, strategic decisions, Seldon dispatches"
    ok "  #mission-briefing"
    create_channel "task-board" "${cat_id}" "Active tasks, handoffs, completions"
    ok "  #task-board"
    create_channel "agent-status" "${cat_id}" "Heartbeats, online/offline, health checks"
    ok "  #agent-status"
    create_channel "alerts" "${cat_id}" "P0 incidents, VETO triggers, escalations"
    ok "  #alerts"
fi

# ENGINEERING
log "Creating ENGINEERING category..."
cat_id=$(create_category "ENGINEERING")
if [ -n "${cat_id}" ]; then
    ok "Category created: ENGINEERING (${cat_id})"
    create_channel "deployments" "${cat_id}" "Daneel deploy logs, docker events"
    ok "  #deployments"
    create_channel "security" "${cat_id}" "Hardin patrol reports, vulnerability scans"
    ok "  #security"
    create_channel "architecture" "${cat_id}" "Infrastructure decisions, system design"
    ok "  #architecture"
    create_channel "bugs" "${cat_id}" "Issue tracking, error logs"
    ok "  #bugs"
fi

# RESEARCH
log "Creating RESEARCH category..."
cat_id=$(create_category "RESEARCH")
if [ -n "${cat_id}" ]; then
    ok "Category created: RESEARCH (${cat_id})"
    create_channel "market-intel" "${cat_id}" "Demerzel + Mis research findings"
    ok "  #market-intel"
    create_channel "competitor-watch" "${cat_id}" "Competitive intel change alerts"
    ok "  #competitor-watch"
    create_channel "reddit-digest" "${cat_id}" "Reddit/forum monitoring summaries"
    ok "  #reddit-digest"
    create_channel "x-twitter-feed" "${cat_id}" "Social media intelligence"
    ok "  #x-twitter-feed"
fi

# CONTENT & CREATIVE
log "Creating CONTENT & CREATIVE category..."
cat_id=$(create_category "CONTENT & CREATIVE")
if [ -n "${cat_id}" ]; then
    ok "Category created: CONTENT & CREATIVE (${cat_id})"
    create_channel "content-pipeline" "${cat_id}" "Arkady content drafts, approvals"
    ok "  #content-pipeline"
    create_channel "design-lab" "${cat_id}" "Magnifico creative briefs, brand assets"
    ok "  #design-lab"
    create_channel "social-media" "${cat_id}" "Social post scheduling, engagement"
    ok "  #social-media"
    create_channel "ad-campaigns" "${cat_id}" "Riose paid media reports, ROAS"
    ok "  #ad-campaigns"
fi

# BUSINESS
log "Creating BUSINESS category..."
cat_id=$(create_category "BUSINESS")
if [ -n "${cat_id}" ]; then
    ok "Category created: BUSINESS (${cat_id})"
    create_channel "sales-pipeline" "${cat_id}" "Preem lead updates, deal progress"
    ok "  #sales-pipeline"
    create_channel "revenue-ops" "${cat_id}" "Mallow revenue tracking, forecasts"
    ok "  #revenue-ops"
    create_channel "trading" "${cat_id}" "Trader + Amaryl positions, alerts"
    ok "  #trading"
    create_channel "weekly-reports" "${cat_id}" "Venabili project summaries, KPIs"
    ok "  #weekly-reports"
fi

echo ""
echo "=========================================="
echo "  Discord setup complete!"
echo "=========================================="
echo ""
echo "  5 categories, 20 channels created"
echo "  Matching channels.json configuration"
echo ""
echo "  Bot invite URL (replace CLIENT_ID):"
echo "  https://discord.com/api/oauth2/authorize?client_id=CLIENT_ID&permissions=8&scope=bot"
echo ""
