#!/usr/bin/env bash
# bd.sh — Beads task DAG CLI
# Manages tasks in .beads/beads.jsonl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BEADS_FILE="$PROJECT_ROOT/.beads/beads.jsonl"

# Ensure beads file exists
if [[ ! -f "$BEADS_FILE" ]]; then
    echo "Error: $BEADS_FILE not found" >&2
    exit 1
fi

# Show tasks that are ready (pending with all blockers completed)
cmd_ready() {
    python3 << 'PYEOF'
import json, sys, os

beads_file = os.environ["BEADS_FILE"]
tasks = {}
order = []
with open(beads_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        t = json.loads(line)
        tasks[t["id"]] = t
        order.append(t["id"])

print("=== Ready Tasks ===")
found = False
for tid in order:
    t = tasks[tid]
    if t["status"] != "pending":
        continue
    blocked_by = t.get("blocked_by", [])
    all_done = all(
        bid in tasks and tasks[bid]["status"] == "completed"
        for bid in blocked_by
    )
    if all_done:
        assigned = t.get("assigned_to", "unassigned")
        print(f"  {t['id']:<10} {t['title']:<40} [{assigned}]")
        found = True

if not found:
    print("  (no ready tasks)")
PYEOF
}

# Show task details
cmd_show() {
    local target_id="$1"
    python3 - "$target_id" << 'PYEOF'
import json, sys, os

target_id = sys.argv[1]
beads_file = os.environ["BEADS_FILE"]

with open(beads_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        t = json.loads(line)
        if t["id"] == target_id:
            print(f"ID:          {t['id']}")
            print(f"Title:       {t['title']}")
            print(f"Status:      {t['status']}")
            print(f"Assigned:    {t.get('assigned_to', 'unassigned')}")
            print(f"Blocks:      {', '.join(t.get('blocks', [])) or 'none'}")
            print(f"Blocked by:  {', '.join(t.get('blocked_by', [])) or 'none'}")
            print(f"Created:     {t.get('created_at', 'unknown')}")
            closed = t.get("closed_at")
            if closed:
                print(f"Closed:      {closed}")
            summary = t.get("summary")
            if summary:
                print(f"Summary:     {summary}")
            sys.exit(0)

print(f"Error: task {target_id} not found", file=sys.stderr)
sys.exit(1)
PYEOF
}

# Create a new task
cmd_create() {
    # Pass all args to python via environment
    python3 - "$@" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

args = sys.argv[1:]
beads_file = os.environ["BEADS_FILE"]

title = ""
blocks = ""
discovered_from = ""
assigned_to = "seldon"

i = 0
while i < len(args):
    if args[i] == "--blocks" and i + 1 < len(args):
        blocks = args[i + 1]
        i += 2
    elif args[i] == "--discovered-from" and i + 1 < len(args):
        discovered_from = args[i + 1]
        i += 2
    elif args[i] == "--assigned-to" and i + 1 < len(args):
        assigned_to = args[i + 1]
        i += 2
    else:
        if not title:
            title = args[i]
        i += 1

if not title:
    print('Error: title required. Usage: bd create "title" [--blocks id] [--discovered-from id]', file=sys.stderr)
    sys.exit(1)

# Find max ID
max_num = 0
with open(beads_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        t = json.loads(line)
        tid = t["id"]
        if tid.startswith("bd-"):
            try:
                num = int(tid[3:])
                if num > max_num:
                    max_num = num
            except ValueError:
                pass

new_id = f"bd-{max_num + 1:03d}"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

blocks_list = [b.strip() for b in blocks.split(",") if b.strip()] if blocks else []
blocked_by_list = [b.strip() for b in discovered_from.split(",") if b.strip()] if discovered_from else []

task = {
    "id": new_id,
    "title": title,
    "status": "pending",
    "blocks": blocks_list,
    "blocked_by": blocked_by_list,
    "assigned_to": assigned_to,
    "created_at": now,
    "closed_at": None,
    "summary": None
}

with open(beads_file, "a") as f:
    f.write(json.dumps(task) + "\n")

print(f"Created task {new_id}: {title}")
PYEOF
}

# Update task status
cmd_update() {
    python3 - "$@" << 'PYEOF'
import json, sys, os, tempfile, shutil

args = sys.argv[1:]
beads_file = os.environ["BEADS_FILE"]

target_id = args[0] if args else ""
new_status = ""

i = 1
while i < len(args):
    if args[i] == "--status" and i + 1 < len(args):
        new_status = args[i + 1]
        i += 2
    else:
        i += 1

if not new_status:
    print("Error: --status required. Usage: bd update <id> --status <status>", file=sys.stderr)
    sys.exit(1)

valid = {"pending", "in-progress", "completed", "blocked"}
if new_status not in valid:
    print(f"Error: invalid status '{new_status}'. Must be: {', '.join(sorted(valid))}", file=sys.stderr)
    sys.exit(1)

lines = []
found = False
with open(beads_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        t = json.loads(line)
        if t["id"] == target_id:
            t["status"] = new_status
            found = True
        lines.append(json.dumps(t))

if not found:
    print(f"Error: task {target_id} not found", file=sys.stderr)
    sys.exit(1)

with open(beads_file, "w") as f:
    for l in lines:
        f.write(l + "\n")

print(f"Updated {target_id} status to {new_status}")
PYEOF
}

# Close a task with summary
cmd_close() {
    python3 - "$@" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

args = sys.argv[1:]
beads_file = os.environ["BEADS_FILE"]

target_id = args[0] if args else ""
summary = ""

i = 1
while i < len(args):
    if args[i] == "--summary" and i + 1 < len(args):
        summary = args[i + 1]
        i += 2
    else:
        i += 1

if not summary:
    print('Error: --summary required. Usage: bd close <id> --summary "..."', file=sys.stderr)
    sys.exit(1)

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lines = []
found = False
with open(beads_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        t = json.loads(line)
        if t["id"] == target_id:
            t["status"] = "completed"
            t["closed_at"] = now
            t["summary"] = summary
            found = True
        lines.append(json.dumps(t))

if not found:
    print(f"Error: task {target_id} not found", file=sys.stderr)
    sys.exit(1)

with open(beads_file, "w") as f:
    for l in lines:
        f.write(l + "\n")

print(f"Closed {target_id}: {summary}")
PYEOF
}

# Sync beads to git
cmd_sync() {
    cd "$PROJECT_ROOT"
    git add .beads/beads.jsonl
    git commit -m "chore: sync beads task graph" || echo "Nothing to commit"
    echo "Beads synced to git"
}

# Usage
usage() {
    cat << 'EOF'
Usage: bd <command> [args]

Commands:
  ready                              Show tasks with no unmet blockers
  show <id>                          Show task details
  create "title" [--blocks id]       Create a new task
         [--discovered-from id]      Link to parent task
         [--assigned-to name]        Assign to agent (default: seldon)
  update <id> --status <status>      Update task status
  close <id> --summary "..."         Complete a task with summary
  sync                               Git add/commit beads.jsonl
EOF
}

# Pass BEADS_FILE to python subprocesses
export BEADS_FILE

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    ready)
        cmd_ready
        ;;
    show)
        if [[ $# -eq 0 ]]; then
            echo "Error: task ID required. Usage: bd show <id>" >&2
            exit 1
        fi
        cmd_show "$1"
        ;;
    create)
        cmd_create "$@"
        ;;
    update)
        if [[ $# -eq 0 ]]; then
            echo "Error: task ID required. Usage: bd update <id> --status <status>" >&2
            exit 1
        fi
        cmd_update "$@"
        ;;
    close)
        if [[ $# -eq 0 ]]; then
            echo "Error: task ID required. Usage: bd close <id> --summary \"...\"" >&2
            exit 1
        fi
        cmd_close "$@"
        ;;
    sync)
        cmd_sync
        ;;
    *)
        echo "Error: unknown command '$command'" >&2
        usage
        exit 1
        ;;
esac
