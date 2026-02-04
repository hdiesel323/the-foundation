#!/usr/bin/env bash
# ============================================================
# Feature #224: Verify commerce/intel patrol configs and intervals
#
# Checks: preem=4h, riose=2h, mallow=daily, trader=30m, amaryl=4h
#
# Run: bash tests/test-patrol-configs.sh
# ============================================================
set -euo pipefail

echo "=== Feature #224: Patrol Config Verification ==="
echo ""

PATROL_DIR="agent-runtime/patrols"
PASS=0
FAIL=0

# Check each patrol exists and has correct interval
check_patrol() {
  local agent="$1"
  local file="$2"
  local expected_interval="$3"
  local interval_field="$4"

  if [ ! -f "$PATROL_DIR/$file" ]; then
    echo "  ✗ $agent patrol: $file not found"
    ((FAIL++))
    return
  fi

  local actual=$(grep "$interval_field" "$PATROL_DIR/$file" | head -1 | grep -oE '[0-9]+')
  if [ "$actual" = "$expected_interval" ]; then
    echo "  ✓ $agent patrol: $file ($interval_field: $actual)"
    ((PASS++))
  else
    echo "  ✗ $agent patrol: expected $interval_field=$expected_interval, got $actual"
    ((FAIL++))
  fi

  # Check dispatch_to seldon
  if grep -q "dispatch_to.*seldon" "$PATROL_DIR/$file"; then
    echo "    → routes through Seldon ✓"
  else
    echo "    → WARNING: may not route through Seldon"
  fi
}

check_patrol "trader" "trader-patrol.ts" "30" "interval_minutes"
check_patrol "riose" "riose-patrol.ts" "2" "interval_hours"
check_patrol "preem" "preem-patrol.ts" "4" "interval_hours"
check_patrol "amaryl" "amaryl-patrol.ts" "4" "interval_hours"
check_patrol "mallow" "mallow-patrol.ts" "24" "interval_hours"

# Also verify mis patrol
check_patrol "mis" "mis-patrol.ts" "6" "interval_hours"

echo ""

# Verify all patrols import PatrolFinding
echo "Checking PatrolFinding type imports..."
for file in preem-patrol.ts riose-patrol.ts mallow-patrol.ts trader-patrol.ts amaryl-patrol.ts mis-patrol.ts; do
  if grep -q "PatrolFinding" "$PATROL_DIR/$file"; then
    echo "  ✓ $file imports PatrolFinding"
    ((PASS++))
  else
    echo "  ✗ $file missing PatrolFinding import"
    ((FAIL++))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "=== PASS ==="
else
  echo "=== FAIL ==="
  exit 1
fi
