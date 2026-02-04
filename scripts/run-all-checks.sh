#!/usr/bin/env bash
set -euo pipefail

# run-all-checks.sh — Validates all config files and scripts in the OpenClaw project.
# Runs: docker compose config, YAML validation, JSON validation, bash -n on all .sh files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

PASS=0
FAIL=0

pass() {
  echo "  [PASS] $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

# --- 1. Docker Compose config ---
echo ""
echo "=== Docker Compose ==="
if docker compose config > /dev/null 2>&1; then
  pass "docker compose config"
else
  fail "docker compose config"
fi

# --- 2. YAML validation ---
echo ""
echo "=== YAML Files ==="
while IFS= read -r -d '' yml; do
  rel="${yml#$PROJECT_ROOT/}"
  if python3 -c "import yaml; yaml.safe_load(open('$yml'))" 2>/dev/null; then
    pass "$rel"
  else
    fail "$rel"
  fi
done < <(find "$PROJECT_ROOT/config" -type f \( -name "*.yml" -o -name "*.yaml" \) -print0)

# --- 3. JSON validation ---
echo ""
echo "=== JSON Files ==="
while IFS= read -r -d '' jsn; do
  rel="${jsn#$PROJECT_ROOT/}"
  if python3 -c "import json; json.load(open('$jsn'))" 2>/dev/null; then
    pass "$rel"
  else
    fail "$rel"
  fi
done < <(find "$PROJECT_ROOT/config" -type f -name "*.json" -print0)

# --- 4. Shell script syntax ---
echo ""
echo "=== Shell Scripts (bash -n) ==="
while IFS= read -r -d '' sh; do
  rel="${sh#$PROJECT_ROOT/}"
  if bash -n "$sh" 2>/dev/null; then
    pass "$rel"
  else
    fail "$rel"
  fi
done < <(find "$PROJECT_ROOT/scripts" -type f -name "*.sh" -print0)

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: SOME CHECKS FAILED"
  exit 1
else
  echo "RESULT: ALL CHECKS PASSED"
  exit 0
fi
