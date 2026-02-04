#!/usr/bin/env bash
# handoff.sh — Cross-agent handoff CLI
# Manages handoffs via the PostgreSQL handoffs table.
# Usage: handoff create --from <agent> --to <agent> --context "..." [--needs "..."] [--acceptance "..."]
#        handoff list [--status pending|completed]
#        handoff complete <id> --result "..."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Docker container and DB settings
PG_CONTAINER="${PG_CONTAINER:-openclaw-postgres}"
PG_USER="${PG_USER:-openclaw}"
PG_DB="${PG_DB:-openclaw}"

# Helper: run a psql query inside the postgres container
psql_query() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" --quiet -tAc "$1" 2>/dev/null
}

psql_formatted() {
    docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "$1" 2>/dev/null
}

# Verify postgres container is running
check_postgres() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
        echo "Error: PostgreSQL container '$PG_CONTAINER' is not running" >&2
        echo "Start it with: docker compose up -d postgres" >&2
        exit 1
    fi
}

# handoff create --from <agent> --to <agent> --context "..." [--needs "..."] [--acceptance "..."]
cmd_create() {
    local from_agent="" to_agent="" context="" needs="" acceptance=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from_agent="$2"; shift 2 ;;
            --to)
                to_agent="$2"; shift 2 ;;
            --context)
                context="$2"; shift 2 ;;
            --needs)
                needs="$2"; shift 2 ;;
            --acceptance)
                acceptance="$2"; shift 2 ;;
            *)
                echo "Error: unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    if [[ -z "$from_agent" || -z "$to_agent" || -z "$context" ]]; then
        echo "Error: --from, --to, and --context are required" >&2
        echo "Usage: handoff create --from <agent> --to <agent> --context \"...\" [--needs \"...\"] [--acceptance \"...\"]" >&2
        exit 1
    fi

    check_postgres

    # Build context JSONB — escape single quotes for SQL
    local context_escaped="${context//\'/\'\'}"
    local needs_escaped="${needs//\'/\'\'}"
    local acceptance_escaped="${acceptance//\'/\'\'}"

    local context_json="{\"description\": \"${context_escaped}\""
    if [[ -n "$needs" ]]; then
        context_json="${context_json}, \"needs\": \"${needs_escaped}\""
    fi
    if [[ -n "$acceptance" ]]; then
        context_json="${context_json}, \"acceptance\": \"${acceptance_escaped}\""
    fi
    context_json="${context_json}}"

    local sql="INSERT INTO handoffs (from_agent, to_agent, context, status)
VALUES ('${from_agent}', '${to_agent}', '${context_json}'::jsonb, 'pending')
RETURNING id::text, created_at::text;"

    local result
    result=$(psql_query "$sql")

    if [[ -z "$result" ]]; then
        echo "Error: failed to create handoff" >&2
        exit 1
    fi

    local handoff_id created_at
    handoff_id=$(echo "$result" | cut -d'|' -f1)
    created_at=$(echo "$result" | cut -d'|' -f2)

    echo "Handoff created:"
    echo "  ID:      $handoff_id"
    echo "  From:    $from_agent"
    echo "  To:      $to_agent"
    echo "  Context: $context"
    [[ -n "$needs" ]] && echo "  Needs:   $needs"
    [[ -n "$acceptance" ]] && echo "  Accept:  $acceptance"
    echo "  Status:  pending"
    echo "  Created: $created_at"
}

# handoff list [--status pending|completed]
cmd_list() {
    local status_filter=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                status_filter="$2"; shift 2 ;;
            *)
                echo "Error: unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    check_postgres

    local where_clause=""
    if [[ -n "$status_filter" ]]; then
        where_clause="WHERE status = '${status_filter}'"
    fi

    local sql="SELECT id::text, from_agent, to_agent, status, created_at::text,
       context->>'description' AS context_desc
FROM handoffs ${where_clause}
ORDER BY created_at DESC
LIMIT 50;"

    echo "=== Handoffs${status_filter:+ (status: $status_filter)} ==="
    psql_formatted "$sql"
}

# handoff complete <id> --result "..."
cmd_complete() {
    local handoff_id="" result_text=""

    if [[ $# -gt 0 && "$1" != --* ]]; then
        handoff_id="$1"; shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --result)
                result_text="$2"; shift 2 ;;
            *)
                echo "Error: unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    if [[ -z "$handoff_id" || -z "$result_text" ]]; then
        echo "Error: handoff ID and --result are required" >&2
        echo "Usage: handoff complete <id> --result \"...\"" >&2
        exit 1
    fi

    check_postgres

    local result_escaped="${result_text//\'/\'\'}"
    local result_json="{\"summary\": \"${result_escaped}\"}"

    local sql="UPDATE handoffs
SET status = 'completed',
    completed_at = NOW(),
    result = '${result_json}'::jsonb
WHERE id = '${handoff_id}'
  AND status = 'pending'
RETURNING id::text, from_agent, to_agent, completed_at::text;"

    local result
    result=$(psql_query "$sql")

    if [[ -z "$result" ]]; then
        echo "Error: handoff '$handoff_id' not found or not in pending status" >&2
        exit 1
    fi

    local from_agent to_agent completed_at
    from_agent=$(echo "$result" | cut -d'|' -f2)
    to_agent=$(echo "$result" | cut -d'|' -f3)
    completed_at=$(echo "$result" | cut -d'|' -f4)

    echo "Handoff completed:"
    echo "  ID:        $handoff_id"
    echo "  From:      $from_agent"
    echo "  To:        $to_agent"
    echo "  Result:    $result_text"
    echo "  Status:    completed"
    echo "  Completed: $completed_at"
}

# Usage help
usage() {
    cat << 'EOF'
Usage: handoff <command> [args]

Commands:
  create --from <agent> --to <agent> --context "..."
         [--needs "..."] [--acceptance "..."]
         Create a new handoff between agents

  list [--status pending|completed]
         List handoffs, optionally filtered by status

  complete <id> --result "..."
         Mark a handoff as completed with result summary
EOF
}

# Main dispatch
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    create)
        cmd_create "$@"
        ;;
    list)
        cmd_list "$@"
        ;;
    complete)
        cmd_complete "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Error: unknown command '$command'" >&2
        usage
        exit 1
        ;;
esac
