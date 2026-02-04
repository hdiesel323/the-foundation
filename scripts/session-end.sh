#!/usr/bin/env bash
# session-end.sh — Capture session observations and persist learnings.
# Implements memory:end_session: writes observations to .learnings/LEARNINGS.md
# and inserts into PostgreSQL insights table.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEARNINGS_DIR="$PROJECT_ROOT/.learnings"
LEARNINGS_FILE="$LEARNINGS_DIR/LEARNINGS.md"

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"
AGENT_ID="${AGENT_ID:-seldon}"

# Session observation parameters (can be passed as env vars or args)
CATEGORY="${CATEGORY:-session_observation}"
SUMMARY="${1:-}"
CONFIDENCE="${CONFIDENCE:-0.80}"
TTL_SECONDS="${TTL_SECONDS:-86400}"  # 24 hours default

if [[ -z "$SUMMARY" ]]; then
    echo "Usage: session-end.sh <summary>"
    echo "  or:  SUMMARY='...' session-end.sh"
    echo ""
    echo "Environment variables:"
    echo "  AGENT_ID     — Agent that ran the session (default: seldon)"
    echo "  CATEGORY     — Insight category (default: session_observation)"
    echo "  CONFIDENCE   — Confidence score 0.00-1.00 (default: 0.80)"
    echo "  TTL_SECONDS  — Time-to-live in seconds (default: 86400 = 24h)"
    exit 1
fi

# Ensure learnings directory exists
mkdir -p "$LEARNINGS_DIR"

# Generate learning ID
DATE_STAMP=$(date '+%Y%m%d')
# Count existing entries for today to generate sequence number
existing_today=0
if [[ -f "$LEARNINGS_FILE" ]]; then
    existing_today=$(grep -c "LEARN-${DATE_STAMP}-" "$LEARNINGS_FILE" 2>/dev/null) || existing_today=0
fi
seq_num=$(printf "%03d" $((existing_today + 1)))
LEARNING_ID="LEARN-${DATE_STAMP}-${seq_num}"

# --- Write to LEARNINGS.md ---
echo "Writing to $LEARNINGS_FILE..."
cat >> "$LEARNINGS_FILE" << EOF

### $LEARNING_ID

- **Date**: $(date '+%Y-%m-%d %H:%M:%S')
- **Agent**: $AGENT_ID
- **Category**: $CATEGORY
- **Confidence**: $CONFIDENCE
- **Summary**: $SUMMARY
- **Status**: captured
EOF

echo "  Appended learning $LEARNING_ID to LEARNINGS.md"

# --- Insert into PostgreSQL insights table ---
# Verify postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "Warning: PostgreSQL container '$PG_CONTAINER' is not running" >&2
    echo "  Learning saved to file but NOT to database." >&2
    echo "  Start postgres and re-run to sync." >&2
    exit 0
fi

# Escape single quotes in summary for SQL
escaped_summary=$(echo "$SUMMARY" | sed "s/'/''/g")

sql="INSERT INTO insights (agent_id, category, content, confidence, ttl_seconds, expires_at, metadata)
VALUES (
    '$AGENT_ID',
    '$CATEGORY',
    \$\$${escaped_summary}\$\$,
    $CONFIDENCE,
    $TTL_SECONDS,
    NOW() + INTERVAL '$TTL_SECONDS seconds',
    jsonb_build_object('learning_id', '$LEARNING_ID', 'source', 'session-end')
);"

if docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$sql" > /dev/null 2>&1; then
    echo "  Inserted insight into PostgreSQL (ID: $LEARNING_ID)"
else
    echo "  Warning: Failed to insert into PostgreSQL" >&2
    echo "  Learning saved to file only." >&2
fi

# --- Log activity ---
activity_sql="INSERT INTO activities (event_type, agent_id, details)
VALUES (
    'project_update',
    '$AGENT_ID',
    jsonb_build_object(
        'summary', \$\$Session ended: ${escaped_summary}\$\$,
        'learning_id', '$LEARNING_ID',
        'action', 'session_end'
    )
);"

docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$activity_sql" > /dev/null 2>&1 || true

echo ""
echo "Session ended. Learning $LEARNING_ID captured."
echo "  File: $LEARNINGS_FILE"
echo "  DB:   insights table (category: $CATEGORY)"
