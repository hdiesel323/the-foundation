#!/usr/bin/env bash
# cartographer-cron.sh — Runs cartographer.sh and auto-commits if codebase map changed
# Designed for cron or patrol scheduling (24h interval recommended)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="$REPO_ROOT/docs/CODEBASE_MAP.md"
CARTOGRAPHER="$REPO_ROOT/scripts/cartographer.sh"

# Ensure cartographer script exists
if [ ! -f "$CARTOGRAPHER" ]; then
  echo "ERROR: cartographer.sh not found at $CARTOGRAPHER" >&2
  exit 1
fi

# Capture previous hash (if file exists)
OLD_HASH=""
if [ -f "$MAP_FILE" ]; then
  OLD_HASH=$(md5sum "$MAP_FILE" 2>/dev/null | awk '{print $1}' || md5 -q "$MAP_FILE" 2>/dev/null || echo "")
fi

# Run cartographer
echo "[cartographer-cron] Running cartographer.sh..."
bash "$CARTOGRAPHER"

# Check if file changed
NEW_HASH=""
if [ -f "$MAP_FILE" ]; then
  NEW_HASH=$(md5sum "$MAP_FILE" 2>/dev/null | awk '{print $1}' || md5 -q "$MAP_FILE" 2>/dev/null || echo "")
fi

if [ "$OLD_HASH" = "$NEW_HASH" ] && [ -n "$OLD_HASH" ]; then
  echo "[cartographer-cron] No changes detected in CODEBASE_MAP.md — skipping commit"
  exit 0
fi

# Auto-commit the updated map
echo "[cartographer-cron] Changes detected — committing updated codebase map"
cd "$REPO_ROOT"
git add docs/CODEBASE_MAP.md
git diff --cached --quiet docs/CODEBASE_MAP.md && {
  echo "[cartographer-cron] File already staged or no diff — skipping commit"
  exit 0
}
git commit -m "chore: auto-update CODEBASE_MAP.md via cartographer patrol"
echo "[cartographer-cron] Committed updated CODEBASE_MAP.md"
