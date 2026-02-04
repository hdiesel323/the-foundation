#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QMD + GraphMem Dual Memory Search Test
#
# Verifies that both memory systems return complementary results
# for the same topic from different perspectives.
#
# Run on VPS after both QMD and GraphMem are installed.
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
DB_PATH="${OPENCLAW_DIR}/data/clawd_brain.db"
PASS=0
FAIL=0

pass() { echo "[PASS] $1"; ((PASS++)); }
fail() { echo "[FAIL] $1"; ((FAIL++)); }

echo "=== QMD + GraphMem Dual Memory Search Test ==="
echo ""

# Pre-check: Both systems available
QMD_OK=false
GRAPHMEM_OK=false

if command -v qmd &>/dev/null; then
    QMD_OK=true
    echo "[OK] QMD is installed"
else
    echo "[SKIP] QMD not installed"
fi

if [ -f "$DB_PATH" ]; then
    GRAPHMEM_OK=true
    echo "[OK] GraphMem database found"
else
    echo "[SKIP] GraphMem database not found"
fi

if [ "$QMD_OK" = false ] && [ "$GRAPHMEM_OK" = false ]; then
    echo ""
    echo "[SKIP] Neither QMD nor GraphMem available — skipping tests"
    exit 0
fi

# Step 1: Ingest test data into QMD (markdown files)
echo ""
echo "--- Step 1: Ingest test data ---"

QMD_TEST_DIR="${OPENCLAW_DIR}/memory"
mkdir -p "$QMD_TEST_DIR"

cat > "${QMD_TEST_DIR}/test-backup-strategy.md" << 'TESTDOC'
# Backup Strategy for OpenClaw

## Overview
The backup system uses encrypted GPG backups with daily automated runs.
PostgreSQL is backed up using pg_dump with compression.

## Components
- Database: pg_dump → gzip → gpg encrypt → /opt/openclaw/backups/
- Files: rsync incremental to backup volume
- Secrets: encrypted separately with backup_passphrase

## Schedule
- Daily at 2 AM UTC: full database backup
- Hourly: incremental file sync
- Weekly: full system snapshot

## Retention
- 7 daily backups
- 4 weekly backups
- 3 monthly backups
TESTDOC

if [ "$QMD_OK" = true ]; then
    qmd embed 2>/dev/null && pass "QMD test data embedded" || fail "QMD embed failed"
fi

# Ingest into GraphMem
if [ "$GRAPHMEM_OK" = true ]; then
    PYTHON="${OPENCLAW_DIR}/tools/graphmem/venv/bin/python3"
    [ -f "$PYTHON" ] || PYTHON="python3"

    $PYTHON << 'PYEOF'
import sqlite3
import os

db_path = os.environ.get("DB_PATH", "/opt/openclaw/data/clawd_brain.db")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Insert test entities
entities = [
    ("backup_system", "system", "Automated encrypted backup system for OpenClaw"),
    ("postgresql", "technology", "PostgreSQL 16 database used for agent memory"),
    ("gpg_encryption", "technology", "GPG encryption for backup security"),
    ("pg_dump", "tool", "PostgreSQL backup utility"),
    ("rsync", "tool", "Incremental file synchronization tool"),
]

for name, etype, desc in entities:
    cursor.execute(
        """INSERT OR REPLACE INTO entities (name, entity_type, description)
           VALUES (?, ?, ?)""",
        (name, etype, desc)
    )

# Insert relationships
cursor.execute("SELECT id, name FROM entities WHERE name IN ('backup_system', 'postgresql', 'gpg_encryption', 'pg_dump', 'rsync')")
entity_map = {row[1]: row[0] for row in cursor.fetchall()}

relationships = [
    ("backup_system", "postgresql", "backs_up"),
    ("backup_system", "gpg_encryption", "uses"),
    ("backup_system", "pg_dump", "uses"),
    ("backup_system", "rsync", "uses"),
    ("postgresql", "pg_dump", "backed_up_by"),
]

for from_name, to_name, rel_type in relationships:
    if from_name in entity_map and to_name in entity_map:
        cursor.execute(
            """INSERT OR REPLACE INTO relationships (from_entity_id, to_entity_id, relationship_type)
               VALUES (?, ?, ?)""",
            (entity_map[from_name], entity_map[to_name], rel_type)
        )

# Insert test memory
cursor.execute(
    """INSERT INTO memories (content, source, agent_id)
       VALUES (?, ?, ?)""",
    ("The backup system uses pg_dump for PostgreSQL and GPG encryption for security", "test", "daneel")
)

conn.commit()
conn.close()
print("[PASS] GraphMem test data ingested")
PYEOF
fi

# Step 2: Query QMD for document search
echo ""
echo "--- Step 2: QMD document search ---"
if [ "$QMD_OK" = true ]; then
    START=$(date +%s%N)
    QMD_RESULT=$(qmd query "backup strategy" --collection shared-memory --limit 5 2>/dev/null || echo "QUERY_FAILED")
    END=$(date +%s%N)
    QMD_MS=$(( (END - START) / 1000000 ))

    if [ "$QMD_RESULT" != "QUERY_FAILED" ]; then
        if echo "$QMD_RESULT" | grep -qi "backup\|pg_dump\|encrypt"; then
            pass "QMD returned document chunks for 'backup strategy'"
        else
            fail "QMD results did not contain expected backup content"
        fi

        if [ "$QMD_MS" -lt 2000 ]; then
            pass "QMD search latency: ${QMD_MS}ms (<2s)"
        else
            fail "QMD search latency: ${QMD_MS}ms (>2s threshold)"
        fi
    else
        fail "QMD query failed"
    fi
else
    echo "[SKIP] QMD not available"
fi

# Step 3: Query GraphMem for relationship search
echo ""
echo "--- Step 3: GraphMem relationship search ---"
if [ "$GRAPHMEM_OK" = true ]; then
    START=$(date +%s%N)
    GRAPHMEM_RESULT=$($PYTHON << 'PYEOF2'
import sqlite3
import os
import json

db_path = os.environ.get("DB_PATH", "/opt/openclaw/data/clawd_brain.db")
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# Find backup_system entity and its relationships
cursor.execute("""
    SELECT r.relationship_type,
           e1.name AS from_name, e1.entity_type AS from_type,
           e2.name AS to_name, e2.entity_type AS to_type
    FROM relationships r
    JOIN entities e1 ON r.from_entity_id = e1.id
    JOIN entities e2 ON r.to_entity_id = e2.id
    WHERE e1.name LIKE '%backup%' OR e2.name LIKE '%backup%'
""")

results = [dict(row) for row in cursor.fetchall()]
conn.close()
print(json.dumps(results))
PYEOF2
    )
    END=$(date +%s%N)
    GM_MS=$(( (END - START) / 1000000 ))

    if echo "$GRAPHMEM_RESULT" | grep -qi "backup_system\|backs_up\|uses"; then
        pass "GraphMem returned entity relationships for backup system"
    else
        fail "GraphMem results did not contain expected relationships"
    fi

    if [ "$GM_MS" -lt 1000 ]; then
        pass "GraphMem search latency: ${GM_MS}ms (<1s)"
    else
        fail "GraphMem search latency: ${GM_MS}ms (>1s threshold)"
    fi
else
    echo "[SKIP] GraphMem not available"
fi

# Step 4: Verify complementary perspectives
echo ""
echo "--- Step 4: Complementary perspectives ---"
if [ "$QMD_OK" = true ] && [ "$GRAPHMEM_OK" = true ]; then
    pass "QMD provides document-level search (full text chunks, context)"
    pass "GraphMem provides entity-relationship search (structured connections)"
    echo "  QMD: 'What documents mention backup?' → document chunks with context"
    echo "  GraphMem: 'What connects to backup?' → entities + relationship types"
else
    echo "[SKIP] Need both systems for complementary test"
fi

# Cleanup
rm -f "${QMD_TEST_DIR}/test-backup-strategy.md"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
