#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# OpenClaw v1 → v2 Full Data Migration
# =====================================================
# Migrates all data from /Users/admin/openclaw (v1) into
# openclaw-002 (v2) — PostgreSQL tables, GraphMem DB,
# agent configs, memory files, business data.
#
# Usage:
#   ./scripts/migrate-v1-to-v2.sh [--dry-run]
#
# Prerequisites:
#   - PostgreSQL running on localhost:5434 (docker compose up postgres)
#   - psql installed (brew install libpq or via postgres.app)
# =====================================================

DRY_RUN="${1:-}"
V1_DIR="/Users/admin/openclaw"
V2_DIR="/Users/admin/openclaw-002"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5434}"
PG_DB="${PG_DB:-openclaw}"
PG_USER="${PG_USER:-openclaw}"
PG_PASS="${PG_PASS:-$(cat "${V2_DIR}/secrets/db_password.txt" 2>/dev/null || echo 'openclaw')}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${V2_DIR}/backups/migration-${TIMESTAMP}.log"

export PGPASSWORD="${PG_PASS}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}  ✓${NC} $*" | tee -a "${LOG_FILE}"; }
warn(){ echo -e "${YELLOW}  ⚠${NC} $*" | tee -a "${LOG_FILE}"; }
err() { echo -e "${RED}  ✗${NC} $*" | tee -a "${LOG_FILE}"; }
dry() { echo -e "${YELLOW}  [DRY RUN]${NC} $*" | tee -a "${LOG_FILE}"; }

run_sql() {
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "SQL: ${1:0:120}..."
        return 0
    fi
    psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" \
        -q -t -A -c "$1" 2>>"${LOG_FILE}"
}

run_sql_file() {
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "SQL FILE: $1"
        return 0
    fi
    psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" \
        -q -f "$1" 2>>"${LOG_FILE}"
}

# =====================================================
echo ""
echo "=========================================="
echo "  OpenClaw v1 → v2 Data Migration"
echo "=========================================="
echo ""

mkdir -p "${V2_DIR}/backups"
echo "Migration started at $(date)" > "${LOG_FILE}"

if [ "${DRY_RUN}" = "--dry-run" ]; then
    warn "DRY RUN MODE — no changes will be made"
    echo ""
fi

# Validate source
if [ ! -d "${V1_DIR}" ]; then
    err "v1 directory not found: ${V1_DIR}"
    exit 1
fi
ok "v1 source: ${V1_DIR}"
ok "v2 target: ${V2_DIR}"

# =====================================================
# STEP 1: Copy GraphMem SQLite database
# =====================================================
log "Step 1: GraphMem database migration"

V1_GRAPHMEM="${V1_DIR}/tools/graphmem/clawd_brain.db"
V2_GRAPHMEM_DIR="${V2_DIR}/mcp-servers/graphmem"

if [ -f "${V1_GRAPHMEM}" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy ${V1_GRAPHMEM} → ${V2_GRAPHMEM_DIR}/clawd_brain.db"
        dry "Would copy cache DB too"
    else
        cp "${V1_GRAPHMEM}" "${V2_GRAPHMEM_DIR}/clawd_brain.db"
        ok "Copied clawd_brain.db ($(du -h "${V1_GRAPHMEM}" | cut -f1))"

        if [ -f "${V1_DIR}/tools/graphmem/clawd_brain.db_cache.db" ]; then
            cp "${V1_DIR}/tools/graphmem/clawd_brain.db_cache.db" "${V2_GRAPHMEM_DIR}/clawd_brain.db_cache.db"
            ok "Copied cache DB"
        fi
    fi
else
    warn "GraphMem DB not found at ${V1_GRAPHMEM}"
fi

# =====================================================
# STEP 2: Copy SOUL.md personality files
# =====================================================
log "Step 2: Agent personality (SOUL) files"

mkdir -p "${V2_DIR}/agents/souls"

# Root SOUL
if [ -f "${V1_DIR}/SOUL.md" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy root SOUL.md"
    else
        cp "${V1_DIR}/SOUL.md" "${V2_DIR}/agents/souls/ROOT-SOUL.md"
        ok "Copied root SOUL.md"
    fi
fi

# Agent SOULs
for soul_file in "${V1_DIR}"/agents/*/SOUL.md; do
    if [ -f "${soul_file}" ]; then
        agent_name=$(basename "$(dirname "${soul_file}")")
        if [ "${DRY_RUN}" = "--dry-run" ]; then
            dry "Would copy ${agent_name}/SOUL.md"
        else
            cp "${soul_file}" "${V2_DIR}/agents/souls/${agent_name}-SOUL.md"
            ok "Copied ${agent_name} SOUL.md"
        fi
    fi
done

# =====================================================
# STEP 3: Import memory files into PostgreSQL facts table
# =====================================================
log "Step 3: Memory files → PostgreSQL facts/insights"

MEMORY_COUNT=0
for mem_file in "${V1_DIR}"/memory/*.md; do
    if [ -f "${mem_file}" ]; then
        fname=$(basename "${mem_file}")
        # Escape single quotes for SQL
        content=$(cat "${mem_file}" | sed "s/'/''/g")
        category="daily_memory"

        # Determine category from filename
        case "${fname}" in
            decisions.md) category="decisions" ;;
            commitments.md) category="commitments" ;;
            b2b-*) category="b2b_prospecting" ;;
            *) category="daily_session" ;;
        esac

        run_sql "INSERT INTO facts (agent_id, category, subject, predicate, object, source, metadata)
            VALUES ('shared', '${category}', '${fname}', 'contains', '${content}',
                    'v1-migration', '{\"migrated_from\": \"${fname}\", \"migration_date\": \"${TIMESTAMP}\"}'::jsonb)
            ON CONFLICT DO NOTHING;"

        MEMORY_COUNT=$((MEMORY_COUNT + 1))
    fi
done
ok "Imported ${MEMORY_COUNT} memory files into facts table"

# =====================================================
# STEP 4: Import decisions into PostgreSQL
# =====================================================
log "Step 4: Decision log → PostgreSQL facts"

if [ -f "${V1_DIR}/memory/decisions.md" ]; then
    content=$(cat "${V1_DIR}/memory/decisions.md" | sed "s/'/''/g")
    run_sql "INSERT INTO facts (agent_id, category, subject, predicate, object, source, metadata)
        VALUES ('shared', 'decision_log', 'v1_decisions', 'recorded', '${content}',
                'v1-migration', '{\"type\": \"decision_log\", \"migration_date\": \"${TIMESTAMP}\"}'::jsonb)
        ON CONFLICT DO NOTHING;"
    ok "Decision log imported"
fi

# =====================================================
# STEP 5: Import B2B prospects into leads table
# =====================================================
log "Step 5: B2B prospects → PostgreSQL leads"

PROSPECTS_FILE="${V1_DIR}/b2b-prospecting/prospects/known-companies.jsonl"
LEAD_COUNT=0

if [ -f "${PROSPECTS_FILE}" ]; then
    while IFS= read -r line; do
        company=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('company',''))" 2>/dev/null || echo "")
        score=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('score',0))" 2>/dev/null || echo "0")
        vertical=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('vertical',''))" 2>/dev/null || echo "")
        reason=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null | sed "s/'/''/g")
        source_type=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','organic'))" 2>/dev/null || echo "organic")
        funding=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('funding',''))" 2>/dev/null | sed "s/'/''/g")
        metadata_json=$(echo "${line}" | sed "s/'/''/g")

        # Map source to allowed enum values
        case "${source_type}" in
            NEWS|JOB_BOARDS*) pg_source="organic" ;;
            REFERRAL) pg_source="referral" ;;
            *) pg_source="organic" ;;
        esac

        if [ -n "${company}" ]; then
            run_sql "INSERT INTO leads (name, company, source, score, notes, tags, metadata)
                VALUES ('${company}', '${company}', '${pg_source}', ${score},
                        '${reason}',
                        ARRAY['${vertical}', 'v1-import'],
                        '{\"funding\": \"${funding}\", \"vertical\": \"${vertical}\", \"migrated\": true}'::jsonb)
                ON CONFLICT DO NOTHING;" || true
            LEAD_COUNT=$((LEAD_COUNT + 1))
        fi
    done < "${PROSPECTS_FILE}"
    ok "Imported ${LEAD_COUNT} B2B prospects into leads table"
else
    warn "No B2B prospects file found"
fi

# =====================================================
# STEP 6: Import competitive intelligence
# =====================================================
log "Step 6: Competitive intel → PostgreSQL"

# Import competitor configs
COMP_CONFIG="${V1_DIR}/competitive-intel/config.json"
COMP_COUNT=0

if [ -f "${COMP_CONFIG}" ]; then
    # Extract competitor names and import
    python3 -c "
import json, sys
with open('${COMP_CONFIG}') as f:
    config = json.load(f)
for vertical_key, vertical in config.get('verticals', {}).items():
    for comp in vertical.get('competitors', []):
        name = comp.get('name', '')
        priority = comp.get('priority', 'medium')
        urls = json.dumps(comp.get('urls', {})).replace(\"'\", \"''\")
        slug = name.lower().replace(' ', '-')
        print(f\"{name}|{slug}|{priority}|{urls}|{vertical_key}\")
" 2>/dev/null | while IFS='|' read -r name slug priority urls vertical; do
        run_sql "INSERT INTO competitors (name, slug, priority, urls, verticals, active)
            VALUES ('${name}', '${slug}', '${priority}', '${urls}'::jsonb,
                    ARRAY['${vertical}'], true)
            ON CONFLICT (slug) DO UPDATE SET
                urls = EXCLUDED.urls,
                priority = EXCLUDED.priority;" || true
        COMP_COUNT=$((COMP_COUNT + 1))
    done
    ok "Imported competitors from config"
fi

# Import change history
CHANGES_FILE="${V1_DIR}/competitive-intel/history/changes.jsonl"
CHANGE_COUNT=0

if [ -f "${CHANGES_FILE}" ]; then
    while IFS= read -r line; do
        competitor=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('competitor',''))" 2>/dev/null || echo "")
        change_type_raw=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('changeType','content'))" 2>/dev/null || echo "content")
        summary=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('summary',''))" 2>/dev/null | sed "s/'/''/g")
        significance=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('significance',0))" 2>/dev/null || echo "0")
        timestamp=$(echo "${line}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('timestamp',''))" 2>/dev/null || echo "")

        # Map change types to allowed enum
        case "${change_type_raw}" in
            pricing) pg_change="pricing" ;;
            product|none) pg_change="product" ;;
            strategic) pg_change="strategic" ;;
            hiring) pg_change="hiring" ;;
            partnership) pg_change="partnership" ;;
            *) pg_change="content" ;;
        esac

        # Clamp significance to 1-10
        if [ "${significance}" -lt 1 ] 2>/dev/null; then significance=1; fi
        if [ "${significance}" -gt 10 ] 2>/dev/null; then significance=10; fi

        if [ -n "${competitor}" ]; then
            slug=$(echo "${competitor}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            run_sql "INSERT INTO competitor_changes (competitor_id, change_type, significance_score, summary, detected_at)
                SELECT c.id, '${pg_change}', ${significance}, '${summary}', '${timestamp}'::timestamptz
                FROM competitors c WHERE c.slug = '${slug}'
                LIMIT 1;" 2>/dev/null || true
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
        fi
    done < "${CHANGES_FILE}"
    ok "Imported ${CHANGE_COUNT} competitive intel change records"
fi

# Copy snapshots directory
if [ -d "${V1_DIR}/competitive-intel/snapshots" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy 66 competitor snapshots"
    else
        mkdir -p "${V2_DIR}/data/competitive-intel/snapshots"
        cp -r "${V1_DIR}/competitive-intel/snapshots/"* "${V2_DIR}/data/competitive-intel/snapshots/" 2>/dev/null || true
        ok "Copied competitor snapshots to data/competitive-intel/snapshots/"
    fi
fi

# Copy weekly reports
if [ -d "${V1_DIR}/competitive-intel/history" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy weekly reports"
    else
        mkdir -p "${V2_DIR}/data/competitive-intel/reports"
        cp "${V1_DIR}"/competitive-intel/history/weekly-report-*.md "${V2_DIR}/data/competitive-intel/reports/" 2>/dev/null || true
        cp "${V1_DIR}"/competitive-intel/SCAN_REPORT_*.md "${V2_DIR}/data/competitive-intel/reports/" 2>/dev/null || true
        ok "Copied competitive intel reports"
    fi
fi

# =====================================================
# STEP 7: Import sentinel metrics into PostgreSQL
# =====================================================
log "Step 7: Sentinel metrics → PostgreSQL metrics"

METRIC_COUNT=0
for metrics_file in "${V1_DIR}"/sentinel/.sentinel-data/metrics/*.jsonl; do
    if [ -f "${metrics_file}" ]; then
        fname=$(basename "${metrics_file}")
        while IFS= read -r line; do
            metric_name=$(echo "${line}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('metric','system_health'))" 2>/dev/null || echo "system_health")
            metric_value=$(echo "${line}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('value', d.get('cpu_percent', d.get('memory_percent', 0))))" 2>/dev/null || echo "0")
            labels=$(echo "${line}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:v for k,v in d.items() if k not in ('metric','value')}))" 2>/dev/null | sed "s/'/''/g")

            run_sql "INSERT INTO metrics (metric_name, metric_value, labels)
                VALUES ('sentinel_${metric_name}', ${metric_value}, '${labels}'::jsonb);" 2>/dev/null || true
            METRIC_COUNT=$((METRIC_COUNT + 1))
        done < "${metrics_file}"
    fi
done
ok "Imported ${METRIC_COUNT} sentinel metrics"

# =====================================================
# STEP 8: Copy patent workspace data
# =====================================================
log "Step 8: Patent workspace data"

if [ -d "${V1_DIR}/agents/patent/workspace" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy patent workspace (496 KB)"
    else
        mkdir -p "${V2_DIR}/data/patent-workspace"
        cp -r "${V1_DIR}/agents/patent/workspace/"* "${V2_DIR}/data/patent-workspace/" 2>/dev/null || true
        ok "Copied patent workspace to data/patent-workspace/"
    fi
fi

# =====================================================
# STEP 9: Copy conversation logs
# =====================================================
log "Step 9: Conversation and skill logs"

if [ -d "${V1_DIR}/skills/molt-space/logs" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy skill logs"
    else
        mkdir -p "${V2_DIR}/data/v1-logs"
        cp "${V1_DIR}"/skills/molt-space/logs/*.jsonl "${V2_DIR}/data/v1-logs/" 2>/dev/null || true
        cp "${V1_DIR}"/skills/molt-space/logs/*.log "${V2_DIR}/data/v1-logs/" 2>/dev/null || true
        ok "Copied conversation/skill logs to data/v1-logs/"
    fi
fi

# =====================================================
# STEP 10: Copy B2B prospecting config
# =====================================================
log "Step 10: B2B prospecting config"

if [ -d "${V1_DIR}/b2b-prospecting" ]; then
    if [ "${DRY_RUN}" = "--dry-run" ]; then
        dry "Would copy B2B config files"
    else
        mkdir -p "${V2_DIR}/data/b2b-prospecting"
        cp "${V1_DIR}/b2b-prospecting/config.json" "${V2_DIR}/data/b2b-prospecting/" 2>/dev/null || true
        cp "${V1_DIR}/b2b-prospecting/prospects/known-companies.jsonl" "${V2_DIR}/data/b2b-prospecting/" 2>/dev/null || true
        ok "Copied B2B prospecting config and raw data"
    fi
fi

# =====================================================
# STEP 11: Log migration activity
# =====================================================
log "Step 11: Recording migration activity"

run_sql "INSERT INTO activities (event_type, agent_id, division, details)
    VALUES ('project_update', 'seldon', 'command',
            '{\"action\": \"v1_migration\", \"timestamp\": \"${TIMESTAMP}\",
              \"memory_files\": ${MEMORY_COUNT}, \"leads\": ${LEAD_COUNT},
              \"metrics\": ${METRIC_COUNT}}'::jsonb);" || true

# =====================================================
# SUMMARY
# =====================================================
echo ""
echo "=========================================="
echo "  Migration Summary"
echo "=========================================="
echo ""
echo "  GraphMem DB:        Copied (clawd_brain.db + cache)"
echo "  SOUL files:         Copied to agents/souls/"
echo "  Memory files:       ${MEMORY_COUNT} → PostgreSQL facts"
echo "  Decision log:       Imported to facts"
echo "  B2B prospects:      ${LEAD_COUNT} → PostgreSQL leads"
echo "  Competitors:        Imported → PostgreSQL competitors"
echo "  Change history:     ${CHANGE_COUNT:-0} → competitor_changes"
echo "  Sentinel metrics:   ${METRIC_COUNT} → PostgreSQL metrics"
echo "  Patent workspace:   Copied to data/patent-workspace/"
echo "  Conversation logs:  Copied to data/v1-logs/"
echo "  Comp. snapshots:    Copied to data/competitive-intel/"
echo ""
echo "  Log: ${LOG_FILE}"
echo ""

if [ "${DRY_RUN}" = "--dry-run" ]; then
    warn "This was a DRY RUN. Run without --dry-run to execute."
else
    ok "Migration complete!"
fi

echo ""
echo "Next steps:"
echo "  1. Review imported data: psql -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} ${PG_DB}"
echo "  2. Populate secrets from v1 .env files (manual — see secrets/*.txt)"
echo "  3. Deploy to VPS: docker compose up -d"
echo ""
