#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Seed GraphMem Knowledge Graph with Architectural Decisions
#
# Seeds the GraphMem SQLite database with key architectural
# decisions as type=Decision entities, each with:
#   - rationale attribute
#   - alternatives_considered attribute
#
# Decisions seeded:
#   1. PostgreSQL over MongoDB (ACID for financial data)
#   2. Docker Compose over K8s (single VPS simplicity)
#   3. Cloudflare Tunnel over exposed ports (zero-trust)
#   4. Prometheus over Datadog (self-hosted cost)
#   5. Foundation naming (Asimov characters for agent identity)
#   6. Bash over Python for ops scripts (simplicity, no deps)
#   7. Slack+Telegram over custom UI (no frontend)
#
# Idempotent: uses ON CONFLICT for upserts.
# ============================================================

DB_PATH="${GRAPHMEM_DB_PATH:-/opt/openclaw/data/clawd_brain.db}"

echo "=== Seeding GraphMem Decisions ==="
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

echo "--- Seeding Decision entities ---"
sqlite3 "$DB_PATH" << 'SQL'
INSERT INTO entities (name, entity_type, description, attributes)
VALUES
  ('decision-postgresql', 'Decision',
   'Use PostgreSQL 16 as single source of truth for all agent memory, preferences, facts, and business data',
   '{"rationale":"Need ACID transactions for financial data, hybrid search (BM25+vector), single database eliminates memory fragmentation across multiple stores","alternatives_considered":["MongoDB (no ACID, eventual consistency)","SQLite (no concurrent writes, single-process)","Redis (volatile, no complex queries)"],"date":"2025-01","status":"final","impact":"critical"}'),

  ('decision-docker-compose', 'Decision',
   'Use Docker Compose for all service orchestration instead of Kubernetes',
   '{"rationale":"Single Hetzner VPS (CPX21, 3 vCPU, 4GB RAM) — K8s overhead exceeds available resources. Compose gives reproducible deployments with minimal complexity","alternatives_considered":["Kubernetes (too heavy for single VPS)","Podman (less ecosystem support)","Bare metal (not reproducible, manual state)"],"date":"2025-01","status":"final","impact":"high"}'),

  ('decision-cloudflare-tunnel', 'Decision',
   'Use Cloudflare Tunnel for all external access — zero exposed ports on VPS',
   '{"rationale":"Zero-trust security model. No inbound ports exposed means no attack surface for port scanning. Cloudflare Access provides SSO/MFA without custom auth code","alternatives_considered":["Exposed ports with UFW (attack surface)","WireGuard VPN (requires client setup)","Tailscale (dependency on third-party mesh)"],"date":"2025-01","status":"final","impact":"high"}'),

  ('decision-prometheus-stack', 'Decision',
   'Use Prometheus + Grafana + Loki for observability instead of SaaS solutions',
   '{"rationale":"Self-hosted keeps cost near zero on existing VPS. Full control over metrics retention and alerting. No per-host or per-metric pricing","alternatives_considered":["Datadog (expensive per-host pricing)","New Relic (usage-based cost escalates)","CloudWatch (AWS lock-in, not on Hetzner)"],"date":"2025-01","status":"final","impact":"medium"}'),

  ('decision-foundation-naming', 'Decision',
   'Name all agents after Isaac Asimov Foundation series characters for consistent identity',
   '{"rationale":"Memorable, distinct names improve team communication. Each character maps to a role archetype (Seldon=planner, Daneel=protector, Hardin=pragmatist). Creates cohesive project identity","alternatives_considered":["Generic names (agent-1, agent-2 — forgettable)","Functional names (router, monitor — clash with system terms)","Random names (no narrative coherence)"],"date":"2025-01","status":"final","impact":"medium"}'),

  ('decision-bash-ops', 'Decision',
   'Use Bash for all operational scripts (backup, restore, health checks, deployment)',
   '{"rationale":"Zero additional dependencies — available on every Linux/Docker image. Ops scripts are glue code calling docker, psql, curl. Python/Node would add unnecessary complexity and startup time","alternatives_considered":["Python (heavier runtime, more deps)","Node.js (startup overhead for simple ops)","Ansible (overkill for single VPS)"],"date":"2025-01","status":"final","impact":"medium"}'),

  ('decision-no-frontend', 'Decision',
   'No custom web frontend — Slack and Telegram as primary interfaces, Grafana for admin',
   '{"rationale":"Agents are conversational by nature. Chat interfaces (Slack Socket Mode, Telegram Bot API) provide the natural interaction model. Grafana covers admin/debug dashboards. Building custom UI would be wasted effort","alternatives_considered":["SvelteKit dashboard (maintenance burden, no clear benefit)","React admin panel (same — chat is the UI)","Retool (SaaS dependency for internal tool)"],"date":"2025-01","status":"final","impact":"medium"}')
ON CONFLICT(name) DO UPDATE SET
  entity_type = excluded.entity_type,
  description = excluded.description,
  attributes = excluded.attributes,
  updated_at = CURRENT_TIMESTAMP;
SQL
echo "[PASS] 7 Decision entities seeded"

echo ""
echo "--- Seeding decision relationships ---"

# Link decisions to the components/entities they affect
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

# Decision APPLIES_TO Component/Division relationships
decision_targets = {
    "decision-postgresql": ["postgres", "Infrastructure"],
    "decision-docker-compose": ["Infrastructure", "daneel"],
    "decision-cloudflare-tunnel": ["cloudflared", "Infrastructure"],
    "decision-prometheus-stack": ["prometheus", "grafana", "loki", "Infrastructure"],
    "decision-foundation-naming": ["Command", "Infrastructure", "Commerce", "Intelligence", "Operations"],
    "decision-bash-ops": ["daneel", "Infrastructure"],
    "decision-no-frontend": ["Operations", "magnifico"],
}

for decision, targets in decision_targets.items():
    for target in targets:
        if upsert_relationship(decision, target, "APPLIES_TO"):
            count += 1

conn.commit()
conn.close()

print(f"[PASS] {count} decision relationships seeded")
PYEOF

# Print summary
echo ""
echo "--- Summary ---"
DECISION_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities WHERE entity_type = 'Decision';")
TOTAL_ENTITIES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM entities;")
REL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM relationships;")

echo "Decision entities:   ${DECISION_COUNT}"
echo "Total entities:      ${TOTAL_ENTITIES}"
echo "Total relationships: ${REL_COUNT}"
echo ""

# Show decisions with their rationale
echo "--- Decisions Seeded ---"
sqlite3 "$DB_PATH" "SELECT name, json_extract(attributes, '$.rationale') FROM entities WHERE entity_type = 'Decision' ORDER BY name;" | while IFS='|' read -r name rationale; do
    echo "  ${name}: ${rationale:0:80}..."
done

echo ""
echo "=== GraphMem Decision Seeding Complete ==="
