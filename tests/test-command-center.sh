#!/bin/bash
# test-command-center.sh — Verify Command Center dashboard and API routes
set -euo pipefail

PASS=0
FAIL=0
SELDON_URL="${SELDON_URL:-http://localhost:18789}"

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "true" ]; then
    echo "  [PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Command Center Tests ==="
echo ""

# --- Static files ---
echo ">> Dashboard files"
check "dashboard/index.html exists" \
  "$([ -f dashboard/index.html ] && echo true || echo false)"

check "dashboard/index.html is valid HTML (has <html> tag)" \
  "$(grep -q '<html' dashboard/index.html && echo true || echo false)"

check "dashboard has dark theme (#0f1117)" \
  "$(grep -q '0f1117' dashboard/index.html && echo true || echo false)"

check "dashboard references /seldon/agents API" \
  "$(grep -q '/seldon/agents' dashboard/index.html && echo true || echo false)"

check "dashboard shows all 14 agents" \
  "$(python3 -c "
import re
with open('dashboard/index.html') as f:
    content = f.read()
agents = ['seldon','daneel','hardin','magnifico','trader','gaal','demerzel','venabili','preem','arkady','mallow','riose','mis','amaryl']
found = sum(1 for a in agents if a in content)
print('true' if found == 14 else 'false')
")"

check "dashboard shows all 5 divisions" \
  "$(python3 -c "
with open('dashboard/index.html') as f:
    content = f.read()
divs = ['command','infrastructure','commerce','intelligence','operations']
found = sum(1 for d in divs if d in content)
print('true' if found == 5 else 'false')
")"

check "dashboard has 30s polling interval" \
  "$(grep -q '30000' dashboard/index.html && echo true || echo false)"

check "dashboard has status dot classes (online/idle/offline)" \
  "$(grep -q 'status-dot' dashboard/index.html && echo true || echo false)"

check "dashboard has click-to-expand (agent-details)" \
  "$(grep -q 'agent-details' dashboard/index.html && echo true || echo false)"

check "dashboard has 3 page views (dashboard/team/settings)" \
  "$(python3 -c "
with open('dashboard/index.html') as f:
    c = f.read()
pages = ['page-dashboard','page-team','page-settings']
print('true' if all(p in c for p in pages) else 'false')
")"

# --- Seldon TypeScript ---
echo ""
echo ">> Seldon API routes"
check "seldon/index.ts has GET /dashboard route" \
  "$(grep -q 'dashboard' seldon/index.ts && echo true || echo false)"

check "seldon/index.ts has GET /seldon/divisions route" \
  "$(grep -q '/seldon/divisions' seldon/index.ts && echo true || echo false)"

check "seldon/index.ts has GET /seldon/status route" \
  "$(grep -q '/seldon/status' seldon/index.ts && echo true || echo false)"

check "seldon/index.ts compiles without errors" \
  "$(cd seldon && npx tsc --noEmit >/dev/null 2>&1 && echo true || echo false)"

# --- Cloudflare tunnel config ---
echo ""
echo ">> Tunnel config"
check "cloudflare tunnel config references /dashboard" \
  "$(grep -rq 'dashboard' config/cloudflare-tunnel.yml 2>/dev/null && echo true || echo false)"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
