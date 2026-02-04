#!/usr/bin/env bash
# beads-sync-pg.sh — Sync .beads/beads.jsonl tasks into PostgreSQL tasks table
# Run after bd sync to keep PostgreSQL in sync with the beads task graph.
# Uses metadata->>'bead_id' for upsert matching (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BEADS_FILE="$PROJECT_ROOT/.beads/beads.jsonl"

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"

if [[ ! -f "$BEADS_FILE" ]]; then
    echo "Error: $BEADS_FILE not found" >&2
    exit 1
fi

# Verify postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "Error: PostgreSQL container '$PG_CONTAINER' is not running" >&2
    exit 1
fi

# Map beads status to tasks table status
# Beads: pending, in-progress, completed, blocked
# Tasks: pending, in_progress, completed, blocked (SQL uses underscores)
map_status() {
    case "$1" in
        in-progress) echo "in_progress" ;;
        *) echo "$1" ;;
    esac
}

synced=0
errors=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Extract fields using jq
    bead_id=$(echo "$line" | jq -r '.id')
    title=$(echo "$line" | jq -r '.title')
    raw_status=$(echo "$line" | jq -r '.status')
    assigned_to=$(echo "$line" | jq -r '.assigned_to // "unassigned"')
    created_at=$(echo "$line" | jq -r '.created_at // empty')
    closed_at=$(echo "$line" | jq -r '.closed_at // empty')
    summary=$(echo "$line" | jq -r '.summary // empty')
    blocks=$(echo "$line" | jq -c '.blocks // []')
    blocked_by=$(echo "$line" | jq -c '.blocked_by // []')

    status=$(map_status "$raw_status")

    # Build metadata JSON with bead-specific fields
    metadata=$(jq -n \
        --arg bead_id "$bead_id" \
        --argjson blocks "$blocks" \
        --argjson blocked_by "$blocked_by" \
        '{bead_id: $bead_id, blocks: $blocks, blocked_by: $blocked_by}')

    # Build result JSON if summary exists
    if [[ -n "$summary" ]]; then
        result=$(jq -n --arg summary "$summary" '{summary: $summary}')
    else
        result="null"
    fi

    # Build SQL for upsert using metadata->>'bead_id' match
    # Check if a row with this bead_id already exists
    sql_check="SELECT id FROM tasks WHERE metadata->>'bead_id' = '${bead_id}' LIMIT 1;"
    existing_uuid=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -tAc "$sql_check" 2>/dev/null || true)

    if [[ -n "$existing_uuid" ]]; then
        # UPDATE existing row
        sql_update="UPDATE tasks SET
            name = \$\$${title}\$\$,
            status = '${status}',
            agent_id = '${assigned_to}',
            completed_at = $(if [[ -n "$closed_at" ]]; then echo "'${closed_at}'"; else echo "NULL"; fi),
            result = $(if [[ "$result" != "null" ]]; then echo "'${result}'::jsonb"; else echo "NULL"; fi),
            metadata = '${metadata}'::jsonb
            WHERE id = '${existing_uuid}';"
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$sql_update" > /dev/null 2>&1
        echo "  Updated: $bead_id ($title)"
    else
        # INSERT new row
        sql_insert="INSERT INTO tasks (agent_id, name, status, created_at, completed_at, result, metadata)
            VALUES (
                '${assigned_to}',
                \$\$${title}\$\$,
                '${status}',
                $(if [[ -n "$created_at" ]]; then echo "'${created_at}'"; else echo "NOW()"; fi),
                $(if [[ -n "$closed_at" ]]; then echo "'${closed_at}'"; else echo "NULL"; fi),
                $(if [[ "$result" != "null" ]]; then echo "'${result}'::jsonb"; else echo "NULL"; fi),
                '${metadata}'::jsonb
            );"
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$sql_insert" > /dev/null 2>&1
        echo "  Inserted: $bead_id ($title)"
    fi

    if [[ $? -eq 0 ]]; then
        synced=$((synced + 1))
    else
        errors=$((errors + 1))
        echo "  ERROR syncing $bead_id" >&2
    fi
done < "$BEADS_FILE"

echo ""
echo "Beads sync complete: $synced synced, $errors errors"
