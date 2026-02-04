#!/usr/bin/env bash
# agent-metrics-collector.sh — Collects per-agent metrics from PostgreSQL
# Outputs Prometheus-compatible text format to /tmp/agent_metrics.prom
# Designed to be run periodically (e.g., via cron or node-exporter textfile collector)
set -euo pipefail

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/agent_metrics.prom}"

# Helper: run a psql query inside the postgres container
psql_query() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" --quiet -tAc "$1" 2>/dev/null
}

# Verify postgres container is running
check_postgres() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
        echo "Error: PostgreSQL container '$PG_CONTAINER' is not running" >&2
        exit 1
    fi
}

check_postgres

# Start fresh output
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# Write HELP and TYPE headers
cat > "$TMPFILE" <<'HEADER'
# HELP openclaw_agent_tasks_completed Total tasks completed per agent.
# TYPE openclaw_agent_tasks_completed counter
# HELP openclaw_agent_handoffs_initiated Total handoffs initiated per agent.
# TYPE openclaw_agent_handoffs_initiated counter
# HELP openclaw_agent_handoffs_received Total handoffs received per agent.
# TYPE openclaw_agent_handoffs_received counter
# HELP openclaw_agent_avg_task_duration_seconds Average task duration in seconds per agent.
# TYPE openclaw_agent_avg_task_duration_seconds gauge
# HELP openclaw_agent_active_hours Total active hours per agent (from activities).
# TYPE openclaw_agent_active_hours gauge
HEADER

# Get all agent IDs
AGENTS=$(psql_query "SELECT id FROM agents ORDER BY id")

if [ -z "$AGENTS" ]; then
    echo "Warning: No agents found in database" >&2
    mv "$TMPFILE" "$OUTPUT_FILE"
    exit 0
fi

while IFS= read -r agent_id; do
    [ -z "$agent_id" ] && continue

    # Tasks completed
    tasks_completed=$(psql_query "SELECT COUNT(*) FROM tasks WHERE agent_id = '$agent_id' AND status = 'completed'")
    tasks_completed="${tasks_completed:-0}"

    # Handoffs initiated (from_agent)
    handoffs_initiated=$(psql_query "SELECT COUNT(*) FROM handoffs WHERE from_agent = '$agent_id'")
    handoffs_initiated="${handoffs_initiated:-0}"

    # Handoffs received (to_agent)
    handoffs_received=$(psql_query "SELECT COUNT(*) FROM handoffs WHERE to_agent = '$agent_id'")
    handoffs_received="${handoffs_received:-0}"

    # Average task duration (seconds) for completed tasks with both started_at and completed_at
    avg_duration=$(psql_query "SELECT COALESCE(EXTRACT(EPOCH FROM AVG(completed_at - started_at)), 0) FROM tasks WHERE agent_id = '$agent_id' AND status = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL")
    avg_duration="${avg_duration:-0}"

    # Active hours: count distinct hours with activity
    active_hours=$(psql_query "SELECT COUNT(DISTINCT date_trunc('hour', created_at)) FROM activities WHERE agent_id = '$agent_id'")
    active_hours="${active_hours:-0}"

    # Write metrics
    echo "openclaw_agent_tasks_completed{agent=\"$agent_id\"} $tasks_completed" >> "$TMPFILE"
    echo "openclaw_agent_handoffs_initiated{agent=\"$agent_id\"} $handoffs_initiated" >> "$TMPFILE"
    echo "openclaw_agent_handoffs_received{agent=\"$agent_id\"} $handoffs_received" >> "$TMPFILE"
    echo "openclaw_agent_avg_task_duration_seconds{agent=\"$agent_id\"} $avg_duration" >> "$TMPFILE"
    echo "openclaw_agent_active_hours{agent=\"$agent_id\"} $active_hours" >> "$TMPFILE"

done <<< "$AGENTS"

# Atomic write to output file
mv "$TMPFILE" "$OUTPUT_FILE"
trap - EXIT

echo "Metrics written to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)"
