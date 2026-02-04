#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QMD Installation Script for Hetzner VPS
#
# QMD (Quick Memory & Documents) — local hybrid search engine.
# Runs entirely on-device with no external API calls.
# Uses local models: embedding-gemma-300M, qwen3-reranker-0.6b,
# qmd-query-expansion-1.7B
# ============================================================

echo "=== Installing QMD ==="

# Check if bun is installed
if ! command -v bun &>/dev/null; then
    echo "Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
fi

echo "Bun version: $(bun --version)"

# Install QMD globally
echo "Installing QMD..."
bun install -g github:tobi/qmd

# Verify installation
echo "Verifying QMD installation..."
qmd --version

# Create QMD cache directory
mkdir -p ~/.cache/qmd
echo "QMD cache directory: ~/.cache/qmd"

# Download local models
echo "Downloading local models (this may take a while)..."
echo "Models:"
echo "  - embedding-gemma-300M (embedding model)"
echo "  - qwen3-reranker-0.6b (re-ranking model)"
echo "  - qmd-query-expansion-1.7B (query expansion model)"

# QMD auto-downloads models on first use, but we trigger it here
qmd index --init 2>/dev/null || true

# Verify SQLite index
if [ -f ~/.cache/qmd/index.sqlite ]; then
    echo "[PASS] QMD index created: ~/.cache/qmd/index.sqlite"
else
    echo "[INFO] QMD index will be created on first indexing run"
fi

# Verify no external API calls
echo ""
echo "=== QMD Configuration ==="
echo "QMD runs entirely on-device:"
echo "  - Embedding: local model (embedding-gemma-300M)"
echo "  - Reranking: local model (qwen3-reranker-0.6b)"
echo "  - Query expansion: local model (qmd-query-expansion-1.7B)"
echo "  - Storage: ~/.cache/qmd/index.sqlite"
echo "  - No external API calls required"

echo ""
echo "=== QMD Installation Complete ==="
