#!/usr/bin/env bash
set -euo pipefail

# health-check.sh — Check all OpenClaw services and report status
# Exit code 0 = all healthy, non-zero = at least one service down

FAIL=0

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" > /dev/null 2>&1; then
    printf "  %-20s [PASS]\n" "$name"
  else
    printf "  %-20s [FAIL]\n" "$name"
    FAIL=1
  fi
}

echo "=== OpenClaw Health Check ==="
echo ""

# --- Database ---
echo "Database:"
check "postgres" "docker exec openclaw-postgres psql -U openclaw -d openclaw -c 'SELECT 1'"

# --- Core Services ---
echo ""
echo "Services:"
check "seldon" "curl -sf http://localhost:18789/health"
check "mcp-gateway" "curl -sf http://localhost:3000/health"

# --- Observability ---
echo ""
echo "Observability:"
check "prometheus" "curl -sf http://localhost:9090/-/healthy"
check "grafana" "curl -sf http://localhost:3001/api/health"
check "loki" "curl -sf http://localhost:3100/ready"

# --- Container Status ---
echo ""
echo "Containers:"
for svc in postgres seldon openclaw mcp-gateway cloudflared prometheus grafana loki promtail; do
  check "$svc" "docker compose ps --format json $svc 2>/dev/null | grep -q '\"running\"'"
done

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "Result: ALL CHECKS PASSED"
else
  echo "Result: ONE OR MORE CHECKS FAILED"
fi

exit "$FAIL"
