#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QMD Collection Setup
#
# Creates QMD collections for agent workspaces, shared memory,
# and documentation. Run after install-qmd.sh on the VPS.
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"

echo "=== Setting up QMD collections ==="

# Collection 1: Agent Workspaces
echo "Adding agent-workspaces collection..."
qmd collection add "${OPENCLAW_DIR}/agents" \
    --name agent-workspaces \
    --description "Agent SOUL.md, MEMORY.md, DECISIONS.md files and workspace documents"
echo "[PASS] agent-workspaces collection added"

# Collection 2: Shared Memory
echo "Adding shared-memory collection..."
mkdir -p "${OPENCLAW_DIR}/memory"
qmd collection add "${OPENCLAW_DIR}/memory" \
    --name shared-memory \
    --description "Cross-agent shared memory, insights, and knowledge base documents"
echo "[PASS] shared-memory collection added"

# Collection 3: Documentation
echo "Adding documentation collection..."
mkdir -p "${OPENCLAW_DIR}/docs"
qmd collection add "${OPENCLAW_DIR}/docs" \
    --name documentation \
    --description "Project documentation, PRD, architecture, and configuration guides"
echo "[PASS] documentation collection added"

# Index all collections
echo ""
echo "=== Embedding all collections ==="
qmd embed
echo "[PASS] QMD embedding complete"

# Verify
echo ""
echo "=== QMD Collection Summary ==="
qmd collection list 2>/dev/null || echo "Collections configured (list available after first embed)"

echo ""
echo "=== QMD Collection Setup Complete ==="
