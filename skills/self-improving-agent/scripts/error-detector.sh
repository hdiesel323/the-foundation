#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Error Detector
#
# Monitors command failures and captures learnings automatically.
# Triggered when a command exits with non-zero status.
#
# Usage: error-detector.sh <exit_code> <command> [agent_id]
# ============================================================

EXIT_CODE="${1:-1}"
FAILED_COMMAND="${2:-unknown}"
AGENT_ID="${3:-shared}"
OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
LEARNINGS_DIR="${OPENCLAW_DIR}/.learnings"
LEARNINGS_FILE="${LEARNINGS_DIR}/LEARNINGS.md"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S%z')
DATE_SHORT=$(date '+%Y%m%d')

# PostgreSQL settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"

mkdir -p "$LEARNINGS_DIR"
mkdir -p "${LEARNINGS_DIR}/archive"

# Generate learning ID
if [ -f "$LEARNINGS_FILE" ]; then
    LAST_NUM=$(grep -oP 'LEARN-\d{8}-\K\d+' "$LEARNINGS_FILE" 2>/dev/null | sort -n | tail -1 || echo "0")
    NEXT_NUM=$((LAST_NUM + 1))
else
    NEXT_NUM=1
fi
LEARN_ID="LEARN-${DATE_SHORT}-$(printf '%03d' "$NEXT_NUM")"

# Classify error
classify_error() {
    local cmd="$1"
    local code="$2"

    case "$cmd" in
        *docker*) echo "infrastructure" ;;
        *git*) echo "infrastructure" ;;
        *psql*|*postgres*) echo "infrastructure" ;;
        *npm*|*node*|*tsc*) echo "infrastructure" ;;
        *curl*|*api*) echo "cross-cutting" ;;
        *) echo "operations" ;;
    esac
}

classify_priority() {
    local code="$1"

    if [ "$code" -ge 128 ]; then
        echo "critical"  # Signal-killed process
    elif [ "$code" -eq 126 ] || [ "$code" -eq 127 ]; then
        echo "high"  # Permission denied or command not found
    else
        echo "medium"
    fi
}

AREA=$(classify_error "$FAILED_COMMAND" "$EXIT_CODE")
PRIORITY=$(classify_priority "$EXIT_CODE")

# Capture the learning
cat >> "$LEARNINGS_FILE" << ENTRY

---

- id: ${LEARN_ID}
  category: error_recovery
  priority: ${PRIORITY}
  area: ${AREA}
  summary: "Command failed: ${FAILED_COMMAND} (exit ${EXIT_CODE})"
  detail: |
    Command: ${FAILED_COMMAND}
    Exit code: ${EXIT_CODE}
    Agent: ${AGENT_ID}
    Timestamp: ${TIMESTAMP}

    Context: Automatic capture by error-detector.sh.
    Review needed to determine root cause and suggested action.
  source:
    agent: "${AGENT_ID}"
    trigger: "command_failure"
    timestamp: "${TIMESTAMP}"
  suggested_action:
    type: no_action
    target: "pending_review"
    content: "Needs manual review to determine corrective action"
  status: captured
ENTRY

echo "[error-detector] Captured learning ${LEARN_ID}: ${FAILED_COMMAND} (exit ${EXIT_CODE})"

# --- Write to PostgreSQL insights table ---
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PG_CONTAINER}$"; then
    escaped_command=$(echo "$FAILED_COMMAND" | sed "s/'/''/g")
    detail_content="Command: ${escaped_command} | Exit code: ${EXIT_CODE} | Agent: ${AGENT_ID} | Priority: ${PRIORITY} | Area: ${AREA}"

    insert_sql="INSERT INTO insights (agent_id, category, content, confidence, ttl_seconds, expires_at, metadata)
    VALUES (
        '${AGENT_ID}',
        'error_recovery',
        \$\$${detail_content}\$\$,
        0.70,
        604800,
        NOW() + INTERVAL '604800 seconds',
        jsonb_build_object(
            'learning_id', '${LEARN_ID}',
            'source', 'error-detector',
            'exit_code', '${EXIT_CODE}',
            'command', \$\$${escaped_command}\$\$,
            'priority', '${PRIORITY}',
            'area', '${AREA}',
            'suggested_action', 'pending_review',
            'timestamp', '${TIMESTAMP}'
        )
    );"

    if docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$insert_sql" > /dev/null 2>&1; then
        echo "[error-detector] Inserted error into PostgreSQL insights (category: error_recovery)"
    else
        echo "[error-detector] Warning: Failed to insert into PostgreSQL" >&2
        echo "  Error captured to file only." >&2
    fi
else
    echo "[error-detector] PostgreSQL container not running — file capture only" >&2
fi

# Check for pattern repetition (same command failing 3+ times)
if [ -f "$LEARNINGS_FILE" ]; then
    FAIL_COUNT=$(grep -c "Command failed: ${FAILED_COMMAND}" "$LEARNINGS_FILE" 2>/dev/null || echo "0")
    if [ "$FAIL_COUNT" -ge 3 ]; then
        echo "[error-detector] WARNING: '${FAILED_COMMAND}' has failed ${FAIL_COUNT} times — pattern detected"

        cat >> "$LEARNINGS_FILE" << PATTERN

---

- id: ${LEARN_ID}-PATTERN
  category: pattern_discovery
  priority: high
  area: ${AREA}
  summary: "Recurring failure pattern: ${FAILED_COMMAND} (${FAIL_COUNT}x)"
  detail: |
    The command '${FAILED_COMMAND}' has failed ${FAIL_COUNT} times.
    This indicates a systemic issue requiring investigation.
  source:
    agent: "${AGENT_ID}"
    trigger: "pattern_repetition"
    timestamp: "${TIMESTAMP}"
  suggested_action:
    type: promote_to_claude_md
    target: "CLAUDE.md"
    content: "Known issue: ${FAILED_COMMAND} frequently fails — investigate root cause"
  status: captured
PATTERN
    fi
fi
