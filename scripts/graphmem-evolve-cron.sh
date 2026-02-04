#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GraphMem Evolution Cron Job
#
# Runs Ebbinghaus forgetting curve decay, PageRank importance
# scoring, entity consolidation, and temporal validity checks.
#
# Install: crontab -e → 0 3 * * * /opt/openclaw/scripts/graphmem-evolve-cron.sh
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
DB_PATH="${OPENCLAW_DIR}/data/clawd_brain.db"
CONFIG_PATH="${OPENCLAW_DIR}/config/graphmem-evolution.json"
LOG_FILE="${OPENCLAW_DIR}/logs/graphmem-evolve.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== GraphMem Evolution Started ==="

if [ ! -f "$DB_PATH" ]; then
    log "[SKIP] Database not found at $DB_PATH"
    exit 0
fi

# Load Python from graphmem venv
PYTHON="${OPENCLAW_DIR}/tools/graphmem/venv/bin/python3"
if [ ! -f "$PYTHON" ]; then
    PYTHON="python3"
fi

$PYTHON << 'PYEOF'
import sqlite3
import math
import json
import os
from datetime import datetime, timedelta

DB_PATH = os.environ.get("DB_PATH", "/opt/openclaw/data/clawd_brain.db")
CONFIG_PATH = os.environ.get("CONFIG_PATH", "/opt/openclaw/config/graphmem-evolution.json")

conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# Load config
config = {}
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH) as f:
        config = json.load(f).get("evolution", {})

stats = {
    "ebbinghaus_decayed": 0,
    "pagerank_computed": False,
    "entities_consolidated": 0,
    "temporal_expired": 0,
    "edges_pruned": 0,
    "orphans_removed": 0,
}

# ============================================================
# 1. Ebbinghaus Forgetting Curve
# retention = e^(-t/S) where t = days since creation, S = stability
# ============================================================
eb_config = config.get("ebbinghaus_forgetting", {})
if eb_config.get("enabled", True):
    base_stability = eb_config.get("base_stability_days", 30)
    min_retention = eb_config.get("minimum_retention", 0.05)
    reinforcement_bonus = eb_config.get("reinforcement_bonus", 1.5)

    # Get all relationships with their age
    cursor.execute("""
        SELECT r.id, r.weight, r.created_at,
               (SELECT COUNT(*) FROM memories m
                WHERE m.entity_ids LIKE '%' || r.from_entity_id || '%'
                   OR m.entity_ids LIKE '%' || r.to_entity_id || '%') AS reference_count
        FROM relationships r
    """)

    for row in cursor.fetchall():
        created = datetime.fromisoformat(row["created_at"]) if row["created_at"] else datetime.now()
        days_old = (datetime.now() - created).days

        # Stability increases with references (reinforcement)
        refs = row["reference_count"] or 0
        stability = base_stability * (reinforcement_bonus ** min(refs, 10))

        # Ebbinghaus: retention = e^(-t/S)
        retention = math.exp(-days_old / stability)
        retention = max(retention, min_retention)

        new_weight = row["weight"] * retention
        if abs(new_weight - row["weight"]) > 0.001:
            cursor.execute(
                "UPDATE relationships SET weight = ? WHERE id = ?",
                (new_weight, row["id"])
            )
            stats["ebbinghaus_decayed"] += 1

    print(f"[PASS] Ebbinghaus decay applied to {stats['ebbinghaus_decayed']} relationships")

# ============================================================
# 2. PageRank Importance Scoring
# ============================================================
pr_config = config.get("pagerank", {})
if pr_config.get("enabled", True):
    damping = pr_config.get("damping_factor", 0.85)
    iterations = pr_config.get("iterations", 20)
    convergence = pr_config.get("convergence_threshold", 0.0001)

    cursor.execute("SELECT id FROM entities")
    entities = [row["id"] for row in cursor.fetchall()]
    n = len(entities)

    if n > 0:
        scores = {eid: 1.0 / n for eid in entities}

        cursor.execute("SELECT from_entity_id, to_entity_id, weight FROM relationships")
        edges = cursor.fetchall()

        for _ in range(iterations):
            new_scores = {eid: (1 - damping) / n for eid in entities}

            out_count = {}
            for edge in edges:
                fid = edge["from_entity_id"]
                out_count[fid] = out_count.get(fid, 0) + 1

            for edge in edges:
                fid = edge["from_entity_id"]
                tid = edge["to_entity_id"]
                w = edge["weight"]
                contribution = damping * (scores.get(fid, 0) / max(out_count.get(fid, 1), 1)) * w
                new_scores[tid] = new_scores.get(tid, 0) + contribution

            # Check convergence
            max_diff = max(abs(new_scores[eid] - scores[eid]) for eid in entities)
            scores = new_scores
            if max_diff < convergence:
                break

        # Store scores
        for eid, score in scores.items():
            cursor.execute(
                """UPDATE entities SET attributes = json_set(
                    COALESCE(attributes, '{}'), '$.pagerank', ?)
                WHERE id = ?""",
                (score, eid)
            )

        stats["pagerank_computed"] = True
        print(f"[PASS] PageRank computed for {n} entities")

# ============================================================
# 3. Entity Consolidation
# ============================================================
cons_config = config.get("consolidation", {})
if cons_config.get("enabled", True):
    # Rule 1: Exact name match (case-insensitive)
    cursor.execute("""
        SELECT LOWER(name) AS lname, GROUP_CONCAT(id) AS ids, COUNT(*) AS cnt
        FROM entities
        GROUP BY LOWER(name)
        HAVING COUNT(*) > 1
    """)

    for row in cursor.fetchall():
        id_list = list(map(int, row["ids"].split(",")))
        keep_id = id_list[0]
        for remove_id in id_list[1:]:
            cursor.execute(
                "UPDATE relationships SET from_entity_id = ? WHERE from_entity_id = ?",
                (keep_id, remove_id)
            )
            cursor.execute(
                "UPDATE relationships SET to_entity_id = ? WHERE to_entity_id = ?",
                (keep_id, remove_id)
            )
            cursor.execute("DELETE FROM entities WHERE id = ?", (remove_id,))
            stats["entities_consolidated"] += 1

    print(f"[PASS] Consolidated {stats['entities_consolidated']} duplicate entities")

# ============================================================
# 4. Temporal Validity
# ============================================================
tv_config = config.get("temporal_validity", {})
if tv_config.get("enabled", True):
    auto_expire_days = tv_config.get("auto_expire_days", 180)

    # Mark old memories as potentially stale
    cutoff = (datetime.now() - timedelta(days=auto_expire_days)).isoformat()
    cursor.execute(
        """UPDATE memories SET source = 'expired'
        WHERE created_at < ? AND source != 'expired'""",
        (cutoff,)
    )
    stats["temporal_expired"] = cursor.rowcount
    print(f"[PASS] Temporal validity: {stats['temporal_expired']} old memories marked expired")

# ============================================================
# 5. Pruning
# ============================================================
prune_config = config.get("pruning", {})
if prune_config.get("enabled", True):
    min_weight = prune_config.get("min_weight_threshold", 0.01)

    cursor.execute("DELETE FROM relationships WHERE weight < ?", (min_weight,))
    stats["edges_pruned"] = cursor.rowcount
    print(f"[PASS] Pruned {stats['edges_pruned']} low-weight edges")

    if prune_config.get("orphan_cleanup", True):
        cursor.execute("""
            DELETE FROM entities WHERE id NOT IN (
                SELECT from_entity_id FROM relationships
                UNION
                SELECT to_entity_id FROM relationships
            ) AND id NOT IN (
                SELECT DISTINCT CAST(value AS INTEGER)
                FROM memories, json_each(memories.entity_ids)
                WHERE memories.entity_ids != '[]'
            )
        """)
        stats["orphans_removed"] = cursor.rowcount
        print(f"[PASS] Removed {stats['orphans_removed']} orphan entities")

conn.commit()
conn.close()

print(f"\n=== Evolution Complete: {json.dumps(stats)} ===")
PYEOF

log "=== GraphMem Evolution Complete ==="
