#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Seed GraphMem Knowledge Graph with Structured Entities
#
# Seeds the GraphMem SQLite database with:
#   - 14 Agent entities (all agents across 5 divisions)
#   - 5 Division entities
#   - 6 Component entities (core infrastructure)
#   - Relationships: BELONGS_TO, OWNS, LED_BY
#
# Idempotent: uses INSERT OR IGNORE / ON CONFLICT for entities,
# INSERT OR REPLACE for relationships.
# ============================================================

DB_PATH="${GRAPHMEM_DB_PATH:-/opt/openclaw/data/clawd_brain.db}"

echo "=== Seeding GraphMem Entities ==="
echo "Database: ${DB_PATH}"
echo ""

# Verify database exists
if [ ! -f "$DB_PATH" ]; then
    echo "[ERROR] GraphMem database not found at ${DB_PATH}"
    echo "Run scripts/install-graphmem.sh first, or set GRAPHMEM_DB_PATH."
    exit 1
fi

# Verify tables exist
TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('entities','relationships');")
if [ "$TABLE_COUNT" -lt 2 ]; then
    echo "[ERROR] Required tables (entities, relationships) not found in database."
    echo "Run scripts/install-graphmem.sh to create schema."
    exit 1
fi

echo "--- Seeding Division entities ---"
sqlite3 "$DB_PATH" << 'SQL'
INSERT INTO entities (name, entity_type, description, attributes)
VALUES
  ('Command', 'Division', 'Top-level orchestration division led by Seldon', '{"priority":"P0","focus":"orchestration"}'),
  ('Infrastructure', 'Division', 'System administration, security, and DevOps', '{"priority":"P1","focus":"sysadmin,security"}'),
  ('Commerce', 'Division', 'Revenue operations, sales, paid media, and trading', '{"priority":"P1","focus":"revenue,sales,trading"}'),
  ('Intelligence', 'Division', 'Research, market intel, and quantitative analysis', '{"priority":"P1","focus":"research,analysis"}'),
  ('Operations', 'Division', 'Creative, project management, and content production', '{"priority":"P1","focus":"creative,content,pm"}')
ON CONFLICT(name) DO UPDATE SET
  entity_type = excluded.entity_type,
  description = excluded.description,
  attributes = excluded.attributes,
  updated_at = CURRENT_TIMESTAMP;
SQL
echo "[PASS] 5 Division entities seeded"

echo ""
echo "--- Seeding Agent entities ---"
sqlite3 "$DB_PATH" << 'SQL'
INSERT INTO entities (name, entity_type, description, attributes)
VALUES
  ('seldon', 'Agent', 'Orchestrator agent — routes tasks, coordinates all divisions', '{"division":"Command","port":18789,"role":"Orchestrator","priority":"P0","host":"mac-mini"}'),
  ('daneel', 'Agent', 'SysAdmin agent — Docker, backups, monitoring, infrastructure', '{"division":"Infrastructure","port":18790,"role":"SysAdmin"}'),
  ('hardin', 'Agent', 'Security agent — audits, hardening, firewall, critic VETO power', '{"division":"Infrastructure","port":18791,"role":"Security","critic":"security-veto"}'),
  ('mallow', 'Agent', 'Revenue Ops VP — pipeline management, deal tracking, forecasting', '{"division":"Commerce","port":18799,"role":"Revenue Ops VP"}'),
  ('preem', 'Agent', 'VP Sales — outreach, lead qualification, CRM operations', '{"division":"Commerce","port":18797,"role":"VP Sales"}'),
  ('riose', 'Agent', 'Paid Media Director — ad campaigns, ROI tracking, budget allocation', '{"division":"Commerce","port":18800,"role":"Paid Media Director"}'),
  ('trader', 'Agent', 'Trading Operations — market analysis, position management, risk', '{"division":"Commerce","port":18793,"role":"Trading Operations"}'),
  ('gaal', 'Agent', 'Research agent — fact-checking, analysis, factual critic VETO power', '{"division":"Intelligence","port":18794,"role":"Research","critic":"factual-veto"}'),
  ('demerzel', 'Agent', 'Chief Intelligence — strategic analysis, threat assessment', '{"division":"Intelligence","port":18795,"role":"Chief Intelligence"}'),
  ('mis', 'Agent', 'VP Research / Market Intel — competitive analysis, market reports', '{"division":"Intelligence","port":18801,"role":"VP Research"}'),
  ('amaryl', 'Agent', 'Quant Analyst — data modeling, statistical analysis, metrics', '{"division":"Intelligence","port":18802,"role":"Quant Analyst"}'),
  ('magnifico', 'Agent', 'Creative Director — primary user interface, content creation', '{"division":"Operations","port":18792,"role":"Creative Director"}'),
  ('venabili', 'Agent', 'Project Manager — task tracking, scheduling, resource allocation', '{"division":"Operations","port":18796,"role":"Project Manager"}'),
  ('arkady', 'Agent', 'Content Writer — blog posts, documentation, copywriting', '{"division":"Operations","port":18798,"role":"Content Writer"}')
ON CONFLICT(name) DO UPDATE SET
  entity_type = excluded.entity_type,
  description = excluded.description,
  attributes = excluded.attributes,
  updated_at = CURRENT_TIMESTAMP;
SQL
echo "[PASS] 14 Agent entities seeded"

echo ""
echo "--- Seeding Component entities ---"
sqlite3 "$DB_PATH" << 'SQL'
INSERT INTO entities (name, entity_type, description, attributes)
VALUES
  ('postgres', 'Component', 'PostgreSQL 16 — single source of truth for all agent memory and business data', '{"service":"openclaw-postgres","port":5432,"image":"postgres:16"}'),
  ('mcp-gateway', 'Component', 'MCP Gateway — routes tool calls to MCP servers, agent communication hub', '{"service":"openclaw","port":18789,"internal_port":8080}'),
  ('cloudflared', 'Component', 'Cloudflare Tunnel — zero-trust secure access, no exposed ports', '{"service":"cloudflared","protocol":"cloudflare-tunnel"}'),
  ('prometheus', 'Component', 'Prometheus — metrics collection and alerting for all services', '{"service":"prometheus","port":9090}'),
  ('grafana', 'Component', 'Grafana — dashboards and visualization for metrics and logs', '{"service":"grafana","port":3000}'),
  ('loki', 'Component', 'Loki — log aggregation and search for all containers', '{"service":"loki","port":3100}')
ON CONFLICT(name) DO UPDATE SET
  entity_type = excluded.entity_type,
  description = excluded.description,
  attributes = excluded.attributes,
  updated_at = CURRENT_TIMESTAMP;
SQL
echo "[PASS] 6 Component entities seeded"

echo ""
echo "--- Seeding relationships ---"

# Build relationships using entity IDs looked up by name.
# Uses a Python helper to handle the logic cleanly with SQLite.
python3 << 'PYEOF'
import sqlite3
import os

db_path = os.environ.get("DB_PATH", os.environ.get("GRAPHMEM_DB_PATH", "/opt/openclaw/data/clawd_brain.db"))
conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys = ON")
cursor = conn.cursor()

def get_entity_id(name):
    row = cursor.execute("SELECT id FROM entities WHERE name = ?", (name,)).fetchone()
    return row[0] if row else None

def upsert_relationship(from_name, to_name, rel_type, weight=1.0):
    from_id = get_entity_id(from_name)
    to_id = get_entity_id(to_name)
    if from_id is None or to_id is None:
        print(f"  [WARN] Skipping {from_name} -> {to_name}: entity not found")
        return False
    cursor.execute("""
        INSERT INTO relationships (from_entity_id, to_entity_id, relationship_type, weight)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(from_entity_id, to_entity_id, relationship_type)
        DO UPDATE SET weight = excluded.weight
    """, (from_id, to_id, rel_type, weight))
    return True

count = 0

# Agent BELONGS_TO Division
agent_divisions = {
    "seldon": "Command",
    "daneel": "Infrastructure",
    "hardin": "Infrastructure",
    "mallow": "Commerce",
    "preem": "Commerce",
    "riose": "Commerce",
    "trader": "Commerce",
    "gaal": "Intelligence",
    "demerzel": "Intelligence",
    "mis": "Intelligence",
    "amaryl": "Intelligence",
    "magnifico": "Operations",
    "venabili": "Operations",
    "arkady": "Operations",
}

for agent, division in agent_divisions.items():
    if upsert_relationship(agent, division, "BELONGS_TO"):
        count += 1

# Division LED_BY Agent (division leaders)
division_leaders = {
    "Command": "seldon",
    "Infrastructure": "daneel",
    "Commerce": "mallow",
    "Intelligence": "demerzel",
    "Operations": "magnifico",
}

for division, leader in division_leaders.items():
    if upsert_relationship(division, leader, "LED_BY"):
        count += 1

# Agent OWNS Component (primary responsibility)
agent_components = {
    "daneel": ["postgres", "prometheus", "grafana", "loki", "cloudflared"],
    "seldon": ["mcp-gateway"],
}

for agent, components in agent_components.items():
    for component in components:
        if upsert_relationship(agent, component, "OWNS"):
            count += 1

conn.commit()
conn.close()

print(f"[PASS] {count} relationships seeded")
PYEOF

# Print summary
echo ""
echo "--- Summary ---"
ENTITY_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities;")
AGENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities WHERE entity_type = 'Agent';")
DIVISION_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities WHERE entity_type = 'Division';")
COMPONENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities WHERE entity_type = 'Component';")
REL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM relationships;")

echo "Total entities:      ${ENTITY_COUNT}"
echo "  Agents:            ${AGENT_COUNT}"
echo "  Divisions:         ${DIVISION_COUNT}"
echo "  Components:        ${COMPONENT_COUNT}"
echo "Total relationships: ${REL_COUNT}"
echo ""
echo "=== GraphMem Entity Seeding Complete ==="
