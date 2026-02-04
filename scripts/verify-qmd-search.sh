#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QMD Hybrid Search Verification
#
# Tests that QMD returns relevant results from agent workspaces.
# Run after install-qmd.sh and setup-qmd-collections.sh on VPS.
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
PASS=0
FAIL=0

pass() { echo "[PASS] $1"; ((PASS++)); }
fail() { echo "[FAIL] $1"; ((FAIL++)); }

echo "=== QMD Hybrid Search Verification ==="
echo ""

# Pre-check: QMD installed
if ! command -v qmd &>/dev/null; then
    echo "[SKIP] QMD not installed — run scripts/install-qmd.sh first"
    exit 0
fi

# Step 1: Create test content in agent workspace
echo "--- Step 1: Create test content ---"
TEST_FILE="${OPENCLAW_DIR}/agents/seldon/test-qmd-verify.md"
cat > "$TEST_FILE" <<'TESTEOF'
# QMD Verification Test Document

This is a test document for verifying QMD hybrid search functionality.
It contains keywords: orchestrator, routing, multi-agent, coordination.
Seldon is the command division orchestrator responsible for task delegation.
TESTEOF
echo "Created test file: $TEST_FILE"
pass "Test content created"

# Step 2: Re-index
echo ""
echo "--- Step 2: Re-embed collections ---"
if qmd embed 2>/dev/null; then
    pass "QMD embed completed"
else
    fail "QMD embed failed"
fi

# Step 3: Query and verify results
echo ""
echo "--- Step 3: Hybrid search test ---"
RESULT=$(qmd query "orchestrator routing delegation" --collection agent-workspaces --limit 5 2>/dev/null || echo "QUERY_FAILED")

if [ "$RESULT" = "QUERY_FAILED" ]; then
    fail "QMD query failed"
else
    if echo "$RESULT" | grep -qi "seldon\|orchestrator\|test-qmd-verify"; then
        pass "Hybrid search returned relevant results"
    else
        fail "Search results did not include expected content"
        echo "  Got: $RESULT"
    fi
fi

# Step 4: Verify hybrid mode (BM25 + vector)
echo ""
echo "--- Step 4: Verify hybrid search combines BM25 + vector ---"
KEYWORD_RESULT=$(qmd query "test-qmd-verify" --collection agent-workspaces --mode keyword --limit 3 2>/dev/null || echo "QUERY_FAILED")
SEMANTIC_RESULT=$(qmd query "agent that coordinates tasks" --collection agent-workspaces --mode semantic --limit 3 2>/dev/null || echo "QUERY_FAILED")
HYBRID_RESULT=$(qmd query "orchestrator coordination" --collection agent-workspaces --mode hybrid --limit 3 2>/dev/null || echo "QUERY_FAILED")

if [ "$KEYWORD_RESULT" != "QUERY_FAILED" ] && [ "$SEMANTIC_RESULT" != "QUERY_FAILED" ] && [ "$HYBRID_RESULT" != "QUERY_FAILED" ]; then
    pass "All search modes (keyword, semantic, hybrid) returned results"
else
    fail "One or more search modes failed"
fi

# Step 5: Performance check (<2 seconds)
echo ""
echo "--- Step 5: Performance check ---"
START=$(date +%s%N)
qmd query "multi-agent system architecture" --collection agent-workspaces --limit 10 >/dev/null 2>&1 || true
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))

if [ "$ELAPSED_MS" -lt 2000 ]; then
    pass "Search completed in ${ELAPSED_MS}ms (<2s threshold)"
else
    fail "Search took ${ELAPSED_MS}ms (>2s threshold)"
fi

# Cleanup
rm -f "$TEST_FILE"
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
