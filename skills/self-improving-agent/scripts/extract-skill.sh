#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Skill Extractor — Foundry Pipeline
#
# Implements the observe → learn → crystallize pipeline:
#   1. OBSERVE: Reads insights with category=pattern_discovery
#      where usage_count >= 3 from PostgreSQL
#   2. LEARN: Generates a skill JSON file in skills/custom/
#   3. CRYSTALLIZE: Inserts into foundry_tools table
#
# Usage:
#   extract-skill.sh                 # Auto-discover and extract all ready patterns
#   extract-skill.sh <insight_id>    # Extract a specific insight by UUID
#   extract-skill.sh --dry-run       # Show what would be extracted without acting
#
# Environment:
#   OPENCLAW_DIR    Base directory (default: /opt/openclaw)
#   PG_CONTAINER    PostgreSQL container name (default: openclaw-postgres)
#   PG_USER         PostgreSQL user (default: openclaw)
#   PG_DB           PostgreSQL database (default: openclaw)
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
SKILLS_DIR="${OPENCLAW_DIR}/skills/custom"
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S%z')
DRY_RUN=false
SPECIFIC_ID=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: extract-skill.sh [--dry-run] [insight_id]"
            echo ""
            echo "Foundry pipeline: observe → learn → crystallize"
            echo "  Reads pattern_discovery insights from PostgreSQL (usage_count >= 3)"
            echo "  Generates skill JSON in skills/custom/"
            echo "  Inserts into foundry_tools table"
            echo ""
            echo "Options:"
            echo "  --dry-run     Show what would be extracted without acting"
            echo "  insight_id    Extract a specific insight by UUID"
            exit 0
            ;;
        *)
            SPECIFIC_ID="$arg"
            ;;
    esac
done

mkdir -p "$SKILLS_DIR"

# ---- STEP 0: Verify PostgreSQL is available ----
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PG_CONTAINER}$"; then
    echo "[extract-skill] ERROR: PostgreSQL container '${PG_CONTAINER}' is not running"
    echo "  Start it with: docker compose up -d postgres"
    exit 1
fi

pg_query() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$1" 2>/dev/null
}

# ---- STEP 1: OBSERVE — Read pattern_discovery insights ----
echo "[extract-skill] === OBSERVE phase ==="

if [ -n "$SPECIFIC_ID" ]; then
    # Extract a specific insight
    QUERY="SELECT id, agent_id, content, metadata
           FROM insights
           WHERE id::text = '${SPECIFIC_ID}'
             AND category = 'pattern_discovery'
           LIMIT 1;"
else
    # Find all pattern_discovery insights with usage_count >= 3
    # usage_count is stored in metadata JSONB field
    QUERY="SELECT id, agent_id, content, metadata
           FROM insights
           WHERE category = 'pattern_discovery'
             AND COALESCE((metadata->>'usage_count')::int, 0) >= 3
             AND NOT COALESCE((metadata->>'extracted')::boolean, false)
           ORDER BY created_at ASC;"
fi

RESULTS=$(pg_query "$QUERY" || echo "")

if [ -z "$RESULTS" ]; then
    echo "[extract-skill] No pattern_discovery insights found with usage_count >= 3"
    echo "  Patterns are created by error-detector.sh when commands fail 3+ times"
    echo "  and written to insights with category='pattern_discovery'"
    exit 0
fi

EXTRACTED=0
SKIPPED=0

# ---- STEP 2 & 3: LEARN + CRYSTALLIZE — Process each insight ----
while IFS='|' read -r insight_id agent_id content metadata; do
    [ -z "$insight_id" ] && continue

    echo ""
    echo "[extract-skill] === LEARN phase: ${insight_id} ==="

    # Generate a skill name from the content
    skill_name=$(echo "$content" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-60)
    if [ -z "$skill_name" ]; then
        skill_name="skill-$(echo "$insight_id" | cut -c1-8)"
    fi

    # Check if skill already exists
    if [ -f "${SKILLS_DIR}/${skill_name}.json" ]; then
        echo "[extract-skill] SKIP: Skill '${skill_name}' already exists"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Check if already in foundry_tools
    existing=$(pg_query "SELECT COUNT(*) FROM foundry_tools WHERE name = '${skill_name}';" || echo "0")
    if [ "$existing" -gt 0 ]; then
        echo "[extract-skill] SKIP: '${skill_name}' already in foundry_tools"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Extract details from metadata
    area=$(echo "$metadata" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('area','general'))" 2>/dev/null || echo "general")
    suggested=$(echo "$metadata" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('suggested_action','review'))" 2>/dev/null || echo "review")
    usage_count=$(echo "$metadata" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('usage_count',3))" 2>/dev/null || echo "3")

    # Build skill description
    description="Auto-extracted skill from pattern: ${content}"

    # Default command is a diagnostic check based on the pattern area
    case "$area" in
        infrastructure) command_str="echo '[${skill_name}] Infrastructure check for: ${content}'" ;;
        cross-cutting)  command_str="echo '[${skill_name}] Cross-cutting check for: ${content}'" ;;
        *)              command_str="echo '[${skill_name}] Operations check for: ${content}'" ;;
    esac

    if $DRY_RUN; then
        echo "[extract-skill] DRY-RUN: Would create skill '${skill_name}'"
        echo "  Agent: ${agent_id}"
        echo "  Content: ${content}"
        echo "  Area: ${area}"
        echo "  Usage count: ${usage_count}"
        EXTRACTED=$((EXTRACTED + 1))
        continue
    fi

    # ---- LEARN: Generate skill JSON ----
    escaped_desc=$(echo "$description" | sed 's/"/\\"/g')
    escaped_cmd=$(echo "$command_str" | sed 's/"/\\"/g')
    escaped_content=$(echo "$content" | sed 's/"/\\"/g')

    cat > "${SKILLS_DIR}/${skill_name}.json" << SKILLJSON
{
  "name": "${skill_name}",
  "description": "${escaped_desc}",
  "command": "${escaped_cmd}",
  "created_by": "foundry",
  "observed_from": "${agent_id}",
  "usage_count": ${usage_count},
  "source_insight_id": "${insight_id}",
  "extracted_at": "${TIMESTAMP}",
  "area": "${area}",
  "original_pattern": "${escaped_content}"
}
SKILLJSON

    echo "[extract-skill] Created skill JSON: skills/custom/${skill_name}.json"

    # Validate the generated JSON
    if ! python3 -c "import json; json.load(open('${SKILLS_DIR}/${skill_name}.json'))" 2>/dev/null; then
        echo "[extract-skill] ERROR: Generated invalid JSON — removing"
        rm -f "${SKILLS_DIR}/${skill_name}.json"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # ---- CRYSTALLIZE: Insert into foundry_tools ----
    echo "[extract-skill] === CRYSTALLIZE phase: ${insight_id} ==="

    escaped_desc_pg=$(echo "$description" | sed "s/'/''/g")
    escaped_cmd_pg=$(echo "$command_str" | sed "s/'/''/g")

    insert_sql="INSERT INTO foundry_tools (name, description, command, created_by, observed_from, usage_count)
    VALUES (
        '${skill_name}',
        \$\$${escaped_desc_pg}\$\$,
        \$\$${escaped_cmd_pg}\$\$,
        'foundry',
        '${agent_id}',
        ${usage_count}
    )
    ON CONFLICT (name) DO UPDATE SET
        usage_count = foundry_tools.usage_count + 1;"

    if pg_query "$insert_sql" > /dev/null 2>&1; then
        echo "[extract-skill] Inserted into foundry_tools: ${skill_name}"
    else
        echo "[extract-skill] WARNING: Failed to insert into foundry_tools" >&2
        echo "  Skill JSON was created but DB insert failed" >&2
    fi

    # Mark insight as extracted so we don't process it again
    mark_sql="UPDATE insights
              SET metadata = metadata || jsonb_build_object('extracted', true, 'extracted_at', '${TIMESTAMP}', 'skill_name', '${skill_name}')
              WHERE id = '${insight_id}'::uuid;"

    pg_query "$mark_sql" > /dev/null 2>&1 || true

    EXTRACTED=$((EXTRACTED + 1))
    echo "[extract-skill] PASS: ${skill_name} crystallized"

done <<< "$RESULTS"

echo ""
echo "[extract-skill] === Pipeline complete ==="
echo "  Extracted: ${EXTRACTED}"
echo "  Skipped:   ${SKIPPED}"

if $DRY_RUN; then
    echo "  (dry-run mode — no changes written)"
fi
