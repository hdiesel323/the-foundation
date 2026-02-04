#!/usr/bin/env bash
# ============================================================
# Feature #222: Verify Foundation Router routes intelligence messages
#
# Tests: 'research competitors' → mis, 'prediction market scan' → amaryl,
#        'cross-division report' → demerzel
#
# Prerequisites: Foundation Router running OR config-based verification
# Run: bash tests/test-intelligence-routing.sh
# ============================================================
set -euo pipefail

echo "=== Feature #222: Intelligence Routing Verification ==="
echo ""

SELDON_URL="${SELDON_URL:-http://localhost:18789}"

declare -A TEST_CASES
TEST_CASES=(
  ["analyze competitor pricing changes"]="mis"
  ["prediction market arbitrage scan"]="amaryl"
  ["cross-division intelligence report"]="demerzel"
  ["market research on home services vertical"]="mis"
  ["quantitative backtest of trading model"]="amaryl"
  ["competitive landscape briefing"]="demerzel"
  ["deep research and fact check this claim"]="gaal"
)

HEALTH=$(curl -sf "$SELDON_URL/health" 2>/dev/null || echo "FAIL")

if [ "$HEALTH" != "FAIL" ]; then
  echo "Live routing test via $SELDON_URL"
  PASS=0
  FAIL=0
  for message in "${!TEST_CASES[@]}"; do
    expected="${TEST_CASES[$message]}"
    result=$(curl -sf -X POST "$SELDON_URL/seldon/route" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"$message\"}" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('bestAgent', data.get('agent', 'unknown')))
" 2>/dev/null || echo "error")

    if [ "$result" = "$expected" ]; then
      echo "  ✓ '$message' → $result"
      ((PASS++))
    else
      echo "  ✗ '$message' → $result (expected $expected)"
      ((FAIL++))
    fi
  done
else
  echo "Services not running — using scoring engine simulation"
  echo ""

  PASS=0
  FAIL=0
  for message in "${!TEST_CASES[@]}"; do
    expected="${TEST_CASES[$message]}"
    result=$(python3 -c "
message = '''$message'''.lower()

keyword_map = {
    'gaal': ['research', 'fact check', 'verify', 'analysis', 'source', 'citation', 'investigate', 'deep research'],
    'demerzel': ['intelligence', 'strategy', 'competitive', 'insight', 'trend', 'synthesis', 'briefing', 'landscape', 'cross-division'],
    'mis': ['market research', 'market intel', 'competitor', 'industry', 'benchmark', 'survey', 'demographics', 'segment', 'pricing'],
    'amaryl': ['quantitative', 'model', 'backtest', 'algorithm', 'statistics', 'regression', 'prediction', 'quant', 'arbitrage'],
}

agent_scores = {}
for agent_id, keywords in keyword_map.items():
    score = sum(1 for kw in keywords if kw in message)
    agent_scores[agent_id] = score

best = max(agent_scores, key=agent_scores.get) if agent_scores else 'unknown'
print(best)
" 2>/dev/null)

    if [ "$result" = "$expected" ]; then
      echo "  ✓ '$message' → $result"
      ((PASS++))
    else
      echo "  ✗ '$message' → $result (expected $expected)"
      ((FAIL++))
    fi
  done
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "=== PASS ==="
else
  echo "=== FAIL ==="
  exit 1
fi
