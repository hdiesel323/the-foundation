#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GraphMem Installation Script
#
# Sets up GraphMem (graph-based knowledge memory) on VPS.
# Creates the SQLite database, installs Python dependencies,
# and configures API keys for entity extraction + embeddings.
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
GRAPHMEM_DIR="${OPENCLAW_DIR}/tools/graphmem"
DATA_DIR="${OPENCLAW_DIR}/data"
DB_PATH="${DATA_DIR}/clawd_brain.db"

echo "=== Installing GraphMem ==="
echo ""

# Step 1: Verify Python 3.10+
echo "--- Checking Python version ---"
PYTHON_CMD=""
for cmd in python3.12 python3.11 python3.10 python3; do
    if command -v "$cmd" &>/dev/null; then
        VERSION=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+')
        MAJOR=$(echo "$VERSION" | cut -d. -f1)
        MINOR=$(echo "$VERSION" | cut -d. -f2)
        if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 10 ]; then
            PYTHON_CMD="$cmd"
            echo "[PASS] Found $cmd (version $VERSION)"
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo "[FAIL] Python 3.10+ not found. Install with: apt install python3.11 python3.11-venv"
    exit 1
fi

# Step 2: Create directories
echo ""
echo "--- Creating directories ---"
mkdir -p "$GRAPHMEM_DIR"
mkdir -p "$DATA_DIR"
echo "[PASS] Directories created"

# Step 3: Set up Python virtual environment
echo ""
echo "--- Setting up Python venv ---"
if [ ! -d "${GRAPHMEM_DIR}/venv" ]; then
    "$PYTHON_CMD" -m venv "${GRAPHMEM_DIR}/venv"
    echo "[PASS] Virtual environment created"
else
    echo "[SKIP] Virtual environment already exists"
fi

# shellcheck disable=SC1091
source "${GRAPHMEM_DIR}/venv/bin/activate"

# Step 4: Install dependencies
echo ""
echo "--- Installing Python dependencies ---"
pip install --upgrade pip --quiet
pip install --quiet \
    requests \
    sqlite-utils \
    numpy \
    openai

echo "[PASS] Dependencies installed"

# Step 5: Create GraphMem database
echo ""
echo "--- Creating GraphMem database ---"
python3 << 'PYEOF'
import sqlite3
import os

db_path = os.environ.get("DB_PATH", "/opt/openclaw/data/clawd_brain.db")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Entities table
cursor.execute("""
CREATE TABLE IF NOT EXISTS entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    entity_type TEXT NOT NULL DEFAULT 'concept',
    description TEXT,
    attributes TEXT DEFAULT '{}',
    embedding BLOB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

# Relationships table (triples: subject-predicate-object)
cursor.execute("""
CREATE TABLE IF NOT EXISTS relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_entity_id INTEGER NOT NULL REFERENCES entities(id),
    to_entity_id INTEGER NOT NULL REFERENCES entities(id),
    relationship_type TEXT NOT NULL,
    weight REAL DEFAULT 1.0,
    metadata TEXT DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(from_entity_id, to_entity_id, relationship_type)
)
""")

# Memories table (raw text with extracted entities)
cursor.execute("""
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    source TEXT DEFAULT 'agent',
    agent_id TEXT,
    entity_ids TEXT DEFAULT '[]',
    embedding BLOB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

# Indexes
cursor.execute("CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_relationships_from ON relationships(from_entity_id)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_relationships_to ON relationships(to_entity_id)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_relationships_type ON relationships(relationship_type)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_memories_agent ON memories(agent_id)")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source)")

conn.commit()
conn.close()
print(f"[PASS] GraphMem database created at {db_path}")
PYEOF

# Step 6: Create config
echo ""
echo "--- Creating GraphMem config ---"
cat > "${GRAPHMEM_DIR}/config.json" << CFGEOF
{
  "database": {
    "path": "${DB_PATH}",
    "type": "sqlite"
  },
  "extraction": {
    "provider": "openrouter",
    "model": "google/gemini-flash-1.5",
    "api_key_env": "OPENROUTER_API_KEY"
  },
  "embedding": {
    "provider": "openai",
    "model": "text-embedding-3-small",
    "dimensions": 1536,
    "api_key_env": "OPENAI_API_KEY"
  },
  "search": {
    "top_k": 10,
    "similarity_threshold": 0.7
  }
}
CFGEOF
echo "[PASS] Config created at ${GRAPHMEM_DIR}/config.json"

deactivate 2>/dev/null || true

echo ""
echo "=== GraphMem Installation Complete ==="
echo "Database: ${DB_PATH}"
echo "Config:   ${GRAPHMEM_DIR}/config.json"
echo "Venv:     ${GRAPHMEM_DIR}/venv/"
echo ""
echo "Required env vars: OPENROUTER_API_KEY, OPENAI_API_KEY"
