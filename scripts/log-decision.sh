#!/usr/bin/env bash
# log-decision.sh — Log architectural decisions to PostgreSQL + GraphMem
#
# Implements memory:log_decision: records decisions in both PostgreSQL facts
# table (category=decision) and GraphMem as Decision entities.
#
# Usage:
#   log-decision.sh --topic "database-choice" \
#                   --decision "PostgreSQL" \
#                   --rationale "Need ACID transactions for financial data" \
#                   --alternatives "MongoDB,SQLite"
#
# Options:
#   --topic          Decision topic/subject (required)
#   --decision       The decision made (required)
#   --rationale      Why this decision was made (required)
#   --alternatives   Comma-separated alternatives considered (optional)
#   --agent          Agent logging the decision (default: shared)
#   --applies-to     Comma-separated component/division names for GraphMem relationships (optional)
#   --dry-run        Show what would be inserted without executing
#   --help           Show this help message
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"

# GraphMem settings
DB_PATH="${GRAPHMEM_DB_PATH:-/opt/openclaw/data/clawd_brain.db}"

# Arguments
TOPIC=""
DECISION=""
RATIONALE=""
ALTERNATIVES=""
AGENT="shared"
APPLIES_TO=""
DRY_RUN=false

usage() {
    echo "Usage: log-decision.sh --topic <topic> --decision <decision> --rationale <rationale> [options]"
    echo ""
    echo "Required:"
    echo "  --topic        Decision topic/subject"
    echo "  --decision     The decision made"
    echo "  --rationale    Why this decision was made"
    echo ""
    echo "Optional:"
    echo "  --alternatives Comma-separated alternatives considered"
    echo "  --agent        Agent logging the decision (default: shared)"
    echo "  --applies-to   Comma-separated component/division names for GraphMem relationships"
    echo "  --dry-run      Show what would be inserted without executing"
    echo "  --help         Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --topic)     TOPIC="$2"; shift 2 ;;
        --decision)  DECISION="$2"; shift 2 ;;
        --rationale) RATIONALE="$2"; shift 2 ;;
        --alternatives) ALTERNATIVES="$2"; shift 2 ;;
        --agent)     AGENT="$2"; shift 2 ;;
        --applies-to) APPLIES_TO="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --help)      usage ;;
        *)           echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate required arguments
if [ -z "$TOPIC" ] || [ -z "$DECISION" ] || [ -z "$RATIONALE" ]; then
    echo "[ERROR] --topic, --decision, and --rationale are required." >&2
    echo "Run with --help for usage." >&2
    exit 1
fi

# Sanitize entity name for GraphMem (lowercase, replace spaces with hyphens)
ENTITY_NAME="decision-$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')"

# Build alternatives JSON array
if [ -n "$ALTERNATIVES" ]; then
    ALT_JSON=$(echo "$ALTERNATIVES" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | python3 -c "
import sys, json
alts = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(alts))
")
else
    ALT_JSON="[]"
fi

# Build metadata JSONB for PostgreSQL
METADATA_JSON=$(python3 -c "
import json, sys
meta = {
    'decision': $(python3 -c "import json; print(json.dumps('$DECISION'))"),
    'rationale': $(python3 -c "import json; print(json.dumps('$RATIONALE'))"),
    'alternatives_considered': $ALT_JSON,
    'date': '$(date -u +%Y-%m-%d)',
    'status': 'final'
}
print(json.dumps(meta))
")

echo "=== Logging Decision ==="
echo "Topic:        ${TOPIC}"
echo "Decision:     ${DECISION}"
echo "Rationale:    ${RATIONALE}"
echo "Alternatives: ${ALTERNATIVES:-none}"
echo "Agent:        ${AGENT}"
echo "Entity name:  ${ENTITY_NAME}"
echo ""

# --- 1. Insert into PostgreSQL facts table ---

# Helper: run a psql query inside the postgres container
psql_query() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" --quiet -tAc "$1" 2>/dev/null
}

# Escape single quotes for SQL
escape_sql() {
    echo "$1" | sed "s/'/''/g"
}

TOPIC_ESC=$(escape_sql "$TOPIC")
DECISION_ESC=$(escape_sql "$DECISION")
RATIONALE_ESC=$(escape_sql "$RATIONALE")
METADATA_ESC=$(escape_sql "$METADATA_JSON")

PG_SQL="INSERT INTO facts (agent_id, category, subject, predicate, object, confidence, source, metadata)
VALUES ('${AGENT}', 'decision', '${TOPIC_ESC}', 'decided', '${DECISION_ESC}', 1.0, 'log-decision.sh', '${METADATA_ESC}'::jsonb)
RETURNING id;"

if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] PostgreSQL INSERT:"
    echo "  $PG_SQL"
    echo ""
else
    # Check if postgres container is running
    if docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
        FACT_ID=$(psql_query "$PG_SQL" || true)
        if [ -n "$FACT_ID" ]; then
            echo "[PASS] PostgreSQL: fact inserted (id: ${FACT_ID})"
        else
            echo "[WARN] PostgreSQL: insert failed or container unavailable (continuing to GraphMem)"
        fi
    else
        echo "[WARN] PostgreSQL container '${PG_CONTAINER}' not running — skipping PostgreSQL insert"
    fi
fi

# --- 2. Insert into GraphMem as Decision entity ---

# Build attributes JSON for GraphMem
GRAPHMEM_ATTRS=$(python3 -c "
import json
attrs = {
    'rationale': $(python3 -c "import json; print(json.dumps('$RATIONALE'))"),
    'alternatives_considered': $ALT_JSON,
    'date': '$(date -u +%Y-%m-%d)',
    'status': 'final',
    'logged_by': '${AGENT}'
}
print(json.dumps(attrs))
")

GRAPHMEM_ATTRS_ESC=$(escape_sql "$GRAPHMEM_ATTRS")
DECISION_DESC_ESC=$(escape_sql "$DECISION")
ENTITY_NAME_ESC=$(escape_sql "$ENTITY_NAME")

GRAPHMEM_SQL="INSERT INTO entities (name, entity_type, description, attributes)
VALUES ('${ENTITY_NAME_ESC}', 'Decision', '${DECISION_DESC_ESC}', '${GRAPHMEM_ATTRS_ESC}')
ON CONFLICT(name) DO UPDATE SET
  entity_type = excluded.entity_type,
  description = excluded.description,
  attributes = excluded.attributes,
  updated_at = CURRENT_TIMESTAMP;"

if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] GraphMem INSERT:"
    echo "  $GRAPHMEM_SQL"
    echo ""
else
    if [ -f "$DB_PATH" ]; then
        sqlite3 "$DB_PATH" "$GRAPHMEM_SQL"
        echo "[PASS] GraphMem: Decision entity '${ENTITY_NAME}' upserted"

        # Create APPLIES_TO relationships if --applies-to provided
        if [ -n "$APPLIES_TO" ]; then
            echo ""
            echo "--- Creating APPLIES_TO relationships ---"
            IFS=',' read -ra TARGETS <<< "$APPLIES_TO"
            REL_COUNT=0
            for target in "${TARGETS[@]}"; do
                target=$(echo "$target" | xargs) # trim whitespace
                target_esc=$(escape_sql "$target")
                # Check if target entity exists
                TARGET_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities WHERE name = '${target_esc}';")
                if [ "$TARGET_EXISTS" -gt 0 ]; then
                    python3 -c "
import sqlite3, os
db = os.environ.get('GRAPHMEM_DB_PATH', '/opt/openclaw/data/clawd_brain.db')
conn = sqlite3.connect(db)
conn.execute('PRAGMA foreign_keys = ON')
cursor = conn.cursor()
from_id = cursor.execute('SELECT id FROM entities WHERE name = ?', ('${ENTITY_NAME_ESC}',)).fetchone()
to_id = cursor.execute('SELECT id FROM entities WHERE name = ?', ('${target_esc}',)).fetchone()
if from_id and to_id:
    cursor.execute('''
        INSERT INTO relationships (from_entity_id, to_entity_id, relationship_type, weight)
        VALUES (?, ?, 'APPLIES_TO', 1.0)
        ON CONFLICT(from_entity_id, to_entity_id, relationship_type)
        DO UPDATE SET weight = excluded.weight
    ''', (from_id[0], to_id[0]))
    conn.commit()
conn.close()
"
                    echo "  [PASS] ${ENTITY_NAME} -> APPLIES_TO -> ${target}"
                    REL_COUNT=$((REL_COUNT + 1))
                else
                    echo "  [WARN] Target entity '${target}' not found in GraphMem — skipping relationship"
                fi
            done
            echo "[PASS] ${REL_COUNT} APPLIES_TO relationships created"
        fi
    else
        echo "[WARN] GraphMem database not found at ${DB_PATH} — skipping GraphMem insert"
    fi
fi

echo ""
echo "=== Decision Logging Complete ==="
