#!/usr/bin/env bash
# session-start.sh — Load recent context from PostgreSQL for agent session startup.
# Implements memory:start_session: queries last 5 insights, last 10 activities,
# and open tasks, then outputs a context summary for the agent context window.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"
AGENT_ID="${AGENT_ID:-seldon}"

# Verify postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "Error: PostgreSQL container '$PG_CONTAINER' is not running" >&2
    echo "Start it with: docker compose up -d postgres" >&2
    exit 1
fi

psql_query() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -tAc "$1" 2>/dev/null
}

echo "=========================================="
echo "  OpenClaw Session Context — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Agent: $AGENT_ID"
echo "=========================================="
echo ""

# --- Recent Insights (last 5, non-expired) ---
echo "## Recent Insights (last 5)"
echo "---"
insights=$(psql_query "
    SELECT category, content, confidence, created_at::date
    FROM insights
    WHERE agent_id = '$AGENT_ID'
      AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 5;
")

if [[ -z "$insights" ]]; then
    echo "  (no recent insights)"
else
    while IFS='|' read -r category content confidence created_at; do
        echo "  [$category] (conf: $confidence, $created_at)"
        echo "    $content"
    done <<< "$insights"
fi
echo ""

# --- Recent Activities (last 10) ---
echo "## Recent Activities (last 10)"
echo "---"
activities=$(psql_query "
    SELECT event_type, agent_id, details->>'summary' AS summary, created_at::timestamp(0)
    FROM activities
    ORDER BY created_at DESC
    LIMIT 10;
")

if [[ -z "$activities" ]]; then
    echo "  (no recent activities)"
else
    while IFS='|' read -r event_type agent details_summary created_at; do
        summary_text=""
        if [[ -n "$details_summary" ]]; then
            summary_text=" — $details_summary"
        fi
        echo "  [$created_at] $event_type by $agent$summary_text"
    done <<< "$activities"
fi
echo ""

# --- Open Tasks ---
echo "## Open Tasks (pending / in_progress)"
echo "---"
tasks=$(psql_query "
    SELECT name, status, agent_id, priority, created_at::date
    FROM tasks
    WHERE status IN ('pending', 'in_progress')
    ORDER BY priority ASC, created_at ASC;
")

if [[ -z "$tasks" ]]; then
    echo "  (no open tasks)"
else
    count=0
    while IFS='|' read -r name status agent priority created_at; do
        count=$((count + 1))
        echo "  $count. [$status] $name (agent: $agent, P$priority, $created_at)"
    done <<< "$tasks"
fi
echo ""

# --- Active Conversations ---
echo "## Active Conversations"
echo "---"
convos=$(psql_query "
    SELECT title, agent_id, last_activity_at::timestamp(0)
    FROM conversations
    WHERE status = 'active'
    ORDER BY last_activity_at DESC
    LIMIT 5;
")

if [[ -z "$convos" ]]; then
    echo "  (no active conversations)"
else
    while IFS='|' read -r title agent last_activity; do
        echo "  [$last_activity] $title (agent: $agent)"
    done <<< "$convos"
fi
echo ""

echo "=========================================="
echo "  Session loaded. Ready to work."
echo "=========================================="
