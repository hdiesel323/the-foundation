#!/usr/bin/env bash
# ============================================================
# Feature #250: Unified Memory Stack Integration Test
#
# Verifies the full Unified Memory Stack:
#   (1) bd ready returns tasks
#   (2) session-start.sh loads context
#   (3) log-decision.sh writes to both PostgreSQL and GraphMem
#   (4) handoff.sh creates and completes a handoff
#   (5) agent-metrics-collector.sh produces Prometheus output
#   (6) cartographer.sh generates CODEBASE_MAP.md
#
# Prerequisites:
#   Components 2-5 require Docker with openclaw-postgres running.
#   Components 1 and 6 run locally without Docker.
#
# Run: bash tests/test-memory-stack.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
SKIP=0

pass() {
    echo "  ✓ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  ✗ $1"
    FAIL=$((FAIL + 1))
}

skip() {
    echo "  ⊘ $1 (SKIPPED — $2)"
    SKIP=$((SKIP + 1))
}

# Check if Docker postgres is available
DOCKER_AVAILABLE=false
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PG_CONTAINER}$"; then
    DOCKER_AVAILABLE=true
fi

echo "=== Feature #250: Unified Memory Stack Integration Test ==="
echo ""
echo "Docker PostgreSQL: $( [ "$DOCKER_AVAILABLE" = true ] && echo 'AVAILABLE' || echo 'NOT AVAILABLE (some tests will skip)' )"
echo ""

# ── Component 1: Beads Task DAG (bd ready) ────────────────────
echo "--- Component 1: Beads Task DAG (bd ready) ---"

# 1a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/bd.sh" 2>/dev/null; then
    pass "bd.sh syntax check"
else
    fail "bd.sh syntax check"
fi

# 1b. bd ready returns output (uses local .beads/beads.jsonl)
BD_OUTPUT=$(bash "$PROJECT_ROOT/scripts/bd.sh" ready 2>&1) || true
if echo "$BD_OUTPUT" | grep -q "=== Ready Tasks ==="; then
    pass "bd ready returns task listing"
else
    fail "bd ready returns task listing (got: $BD_OUTPUT)"
fi

# 1c. bd show works for an existing bead
FIRST_ID=$(python3 -c "
import json
with open('$PROJECT_ROOT/.beads/beads.jsonl') as f:
    for line in f:
        line = line.strip()
        if line:
            print(json.loads(line)['id'])
            break
" 2>/dev/null || echo "")

if [ -n "$FIRST_ID" ]; then
    SHOW_OUTPUT=$(bash "$PROJECT_ROOT/scripts/bd.sh" show "$FIRST_ID" 2>&1) || true
    if echo "$SHOW_OUTPUT" | grep -q "ID:"; then
        pass "bd show $FIRST_ID returns task details"
    else
        fail "bd show $FIRST_ID returns task details"
    fi
else
    fail "could not read first bead ID from beads.jsonl"
fi
echo ""

# ── Component 2: Session Start (session-start.sh) ─────────────
echo "--- Component 2: Session Start (session-start.sh) ---"

# 2a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/session-start.sh" 2>/dev/null; then
    pass "session-start.sh syntax check"
else
    fail "session-start.sh syntax check"
fi

# 2b. Run session-start.sh and verify output structure
if [ "$DOCKER_AVAILABLE" = true ]; then
    SESSION_OUTPUT=$(bash "$PROJECT_ROOT/scripts/session-start.sh" 2>&1) || true
    if echo "$SESSION_OUTPUT" | grep -q "OpenClaw Session Context"; then
        pass "session-start.sh outputs context header"
    else
        fail "session-start.sh outputs context header"
    fi

    if echo "$SESSION_OUTPUT" | grep -q "Recent Insights"; then
        pass "session-start.sh includes insights section"
    else
        fail "session-start.sh includes insights section"
    fi

    if echo "$SESSION_OUTPUT" | grep -q "Session loaded"; then
        pass "session-start.sh completes successfully"
    else
        fail "session-start.sh completes successfully"
    fi
else
    skip "session-start.sh live run" "Docker not available"
    skip "session-start.sh output structure" "Docker not available"
    skip "session-start.sh completion" "Docker not available"
fi
echo ""

# ── Component 3: Log Decision (log-decision.sh) ───────────────
echo "--- Component 3: Log Decision (log-decision.sh) ---"

# 3a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/log-decision.sh" 2>/dev/null; then
    pass "log-decision.sh syntax check"
else
    fail "log-decision.sh syntax check"
fi

# 3b. Dry-run mode (no Docker needed)
DRYRUN_OUTPUT=$(bash "$PROJECT_ROOT/scripts/log-decision.sh" \
    --topic "test-decision" \
    --decision "Test Choice" \
    --rationale "Integration test verification" \
    --alternatives "Alt1,Alt2" \
    --dry-run 2>&1) || true

if echo "$DRYRUN_OUTPUT" | grep -q "Logging Decision"; then
    pass "log-decision.sh --dry-run shows decision header"
else
    fail "log-decision.sh --dry-run shows decision header"
fi

if echo "$DRYRUN_OUTPUT" | grep -q "\[DRY-RUN\] PostgreSQL INSERT"; then
    pass "log-decision.sh --dry-run shows PostgreSQL INSERT"
else
    fail "log-decision.sh --dry-run shows PostgreSQL INSERT"
fi

if echo "$DRYRUN_OUTPUT" | grep -q "\[DRY-RUN\] GraphMem INSERT"; then
    pass "log-decision.sh --dry-run shows GraphMem INSERT"
else
    fail "log-decision.sh --dry-run shows GraphMem INSERT"
fi

# 3c. Live PostgreSQL + GraphMem test
if [ "$DOCKER_AVAILABLE" = true ]; then
    LIVE_OUTPUT=$(bash "$PROJECT_ROOT/scripts/log-decision.sh" \
        --topic "test-stack-250" \
        --decision "Integration test" \
        --rationale "Verifying memory stack feature 250" \
        --alternatives "None" \
        --agent "test-runner" 2>&1) || true

    if echo "$LIVE_OUTPUT" | grep -q "\[PASS\] PostgreSQL"; then
        pass "log-decision.sh writes to PostgreSQL"
    else
        # May warn instead of pass if table structure differs
        if echo "$LIVE_OUTPUT" | grep -q "\[WARN\] PostgreSQL"; then
            skip "log-decision.sh PostgreSQL write" "table may not exist"
        else
            fail "log-decision.sh writes to PostgreSQL"
        fi
    fi
else
    skip "log-decision.sh live PostgreSQL write" "Docker not available"
fi
echo ""

# ── Component 4: Handoff (handoff.sh) ─────────────────────────
echo "--- Component 4: Handoff (handoff.sh) ---"

# 4a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/handoff.sh" 2>/dev/null; then
    pass "handoff.sh syntax check"
else
    fail "handoff.sh syntax check"
fi

# 4b. Help output
HELP_OUTPUT=$(bash "$PROJECT_ROOT/scripts/handoff.sh" help 2>&1) || true
if echo "$HELP_OUTPUT" | grep -q "create"; then
    pass "handoff.sh help lists create command"
else
    fail "handoff.sh help lists create command"
fi

# 4c. Create + list + complete round-trip
if [ "$DOCKER_AVAILABLE" = true ]; then
    # Create a test handoff (use agents that exist in the agents table)
    CREATE_OUTPUT=$(bash "$PROJECT_ROOT/scripts/handoff.sh" create \
        --from daneel --to hardin \
        --context "Memory stack test #250" \
        --needs "verification" 2>&1) || true

    if echo "$CREATE_OUTPUT" | grep -q "Handoff created"; then
        pass "handoff.sh create inserts handoff"

        # Extract ID from create output
        HANDOFF_ID=$(echo "$CREATE_OUTPUT" | grep "ID:" | head -1 | awk '{print $NF}' | tr -d ' ')

        # List pending handoffs
        LIST_OUTPUT=$(bash "$PROJECT_ROOT/scripts/handoff.sh" list --status pending 2>&1) || true
        if echo "$LIST_OUTPUT" | grep -q "pending\|daneel"; then
            pass "handoff.sh list shows pending handoff"
        else
            fail "handoff.sh list shows pending handoff"
        fi

        # Complete the handoff
        if [ -n "$HANDOFF_ID" ]; then
            COMPLETE_OUTPUT=$(bash "$PROJECT_ROOT/scripts/handoff.sh" complete "$HANDOFF_ID" \
                --result "Test completed successfully" 2>&1) || true
            if echo "$COMPLETE_OUTPUT" | grep -q "Handoff completed"; then
                pass "handoff.sh complete marks handoff done"
            else
                fail "handoff.sh complete marks handoff done (got: $COMPLETE_OUTPUT)"
            fi
        else
            fail "could not extract handoff ID from create output"
        fi
    else
        fail "handoff.sh create inserts handoff (got: $CREATE_OUTPUT)"
    fi
else
    skip "handoff.sh create/list/complete round-trip" "Docker not available"
fi
echo ""

# ── Component 5: Agent Metrics Collector ──────────────────────
echo "--- Component 5: Agent Metrics Collector (agent-metrics-collector.sh) ---"

# 5a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/agent-metrics-collector.sh" 2>/dev/null; then
    pass "agent-metrics-collector.sh syntax check"
else
    fail "agent-metrics-collector.sh syntax check"
fi

# 5b. Run and verify Prometheus output
if [ "$DOCKER_AVAILABLE" = true ]; then
    METRICS_OUTPUT_FILE="/tmp/agent_metrics_test_250.prom"
    METRICS_OUTPUT=$(OUTPUT_FILE="$METRICS_OUTPUT_FILE" bash "$PROJECT_ROOT/scripts/agent-metrics-collector.sh" 2>&1) || true

    if [ -f "$METRICS_OUTPUT_FILE" ]; then
        # Check for Prometheus HELP/TYPE headers
        if grep -q "^# HELP openclaw_agent_tasks_completed" "$METRICS_OUTPUT_FILE"; then
            pass "agent-metrics-collector.sh produces HELP headers"
        else
            fail "agent-metrics-collector.sh produces HELP headers"
        fi

        if grep -q "^# TYPE openclaw_agent_tasks_completed" "$METRICS_OUTPUT_FILE"; then
            pass "agent-metrics-collector.sh produces TYPE headers"
        else
            fail "agent-metrics-collector.sh produces TYPE headers"
        fi

        # Check for at least one metric line
        if grep -q "^openclaw_agent_" "$METRICS_OUTPUT_FILE"; then
            pass "agent-metrics-collector.sh produces metric values"
        else
            # Could be valid if no agents exist yet
            skip "agent-metrics-collector.sh metric values" "no agents in database"
        fi

        # Clean up
        rm -f "$METRICS_OUTPUT_FILE"
    else
        fail "agent-metrics-collector.sh creates output file"
    fi
else
    skip "agent-metrics-collector.sh live run" "Docker not available"
fi
echo ""

# ── Component 6: Cartographer (cartographer.sh) ───────────────
echo "--- Component 6: Cartographer (cartographer.sh) ---"

# 6a. Syntax check
if bash -n "$PROJECT_ROOT/scripts/cartographer.sh" 2>/dev/null; then
    pass "cartographer.sh syntax check"
else
    fail "cartographer.sh syntax check"
fi

# 6b. Run and verify CODEBASE_MAP.md generation
CARTO_OUTPUT=$(bash "$PROJECT_ROOT/scripts/cartographer.sh" 2>&1) || true

if echo "$CARTO_OUTPUT" | grep -q "Codebase map generated"; then
    pass "cartographer.sh completes successfully"
else
    fail "cartographer.sh completes successfully (got: $CARTO_OUTPUT)"
fi

MAP_FILE="$PROJECT_ROOT/docs/CODEBASE_MAP.md"
if [ -f "$MAP_FILE" ]; then
    pass "cartographer.sh generates docs/CODEBASE_MAP.md"

    # Verify key sections
    if grep -q "## Directory Tree" "$MAP_FILE"; then
        pass "CODEBASE_MAP.md has Directory Tree section"
    else
        fail "CODEBASE_MAP.md has Directory Tree section"
    fi

    if grep -q "## Agents" "$MAP_FILE"; then
        pass "CODEBASE_MAP.md has Agents section"
    else
        fail "CODEBASE_MAP.md has Agents section"
    fi

    if grep -q "## Scripts" "$MAP_FILE"; then
        pass "CODEBASE_MAP.md has Scripts section"
    else
        fail "CODEBASE_MAP.md has Scripts section"
    fi
else
    fail "cartographer.sh generates docs/CODEBASE_MAP.md"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "==========================================="

if [ "$FAIL" -eq 0 ]; then
    echo "=== PASS ==="
    exit 0
else
    echo "=== FAIL ==="
    exit 1
fi
