#!/usr/bin/env bash
# ============================================================
# Feature #223: Verify critic chains with hardin (security VETO)
# and gaal (factual VETO)
#
# Prerequisites: Services running OR config-based verification
# Run: bash tests/test-critic-chain.sh
# ============================================================
set -euo pipefail

echo "=== Feature #223: Critic Chain Verification ==="
echo ""

PASS=0
FAIL=0

# Verify config structure
echo "Checking critic-chains.json configuration..."

# 1. Security chain has hardin with VETO
HARDIN_VETO=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
sec = cc['critic_chains']['security']
for layer in sec['layers']:
    if layer['agent'] == 'hardin' and layer.get('authority') == 'VETO':
        print('yes')
        break
else:
    print('no')
")
if [ "$HARDIN_VETO" = "yes" ]; then
  echo "  ✓ Security chain: hardin has VETO authority"
  ((PASS++))
else
  echo "  ✗ Security chain: hardin missing VETO authority"
  ((FAIL++))
fi

# 2. Research chain has gaal with VETO
GAAL_VETO=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
res = cc['critic_chains']['research']
for layer in res['layers']:
    if layer['agent'] == 'gaal' and layer.get('authority') == 'VETO':
        print('yes')
        break
else:
    print('no')
")
if [ "$GAAL_VETO" = "yes" ]; then
  echo "  ✓ Research chain: gaal has VETO authority"
  ((PASS++))
else
  echo "  ✗ Research chain: gaal missing VETO authority"
  ((FAIL++))
fi

# 3. Content chain routes through gaal for fact-check
CONTENT_GAAL=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
content = cc['critic_chains']['content']
for layer in content['layers']:
    if layer['agent'] == 'gaal' and layer.get('authority') == 'VETO':
        print('yes')
        break
else:
    print('no')
")
if [ "$CONTENT_GAAL" = "yes" ]; then
  echo "  ✓ Content chain: gaal has factual VETO"
  ((PASS++))
else
  echo "  ✗ Content chain: gaal missing factual VETO"
  ((FAIL++))
fi

# 4. Trading chain has hardin security review
TRADING_HARDIN=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
trading = cc['critic_chains']['trading']
for layer in trading['layers']:
    if layer['agent'] == 'hardin' and layer.get('authority') == 'VETO':
        print('yes')
        break
else:
    print('no')
")
if [ "$TRADING_HARDIN" = "yes" ]; then
  echo "  ✓ Trading chain: hardin has security VETO"
  ((PASS++))
else
  echo "  ✗ Trading chain: hardin missing security VETO"
  ((FAIL++))
fi

# 5. Preem and arkady NOT in any critic chain
NO_PREEM_ARKADY=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
all_agents = []
for chain in cc['critic_chains'].values():
    for layer in chain['layers']:
        all_agents.append(layer['agent'])
if 'preem' not in all_agents and 'arkady' not in all_agents:
    print('yes')
else:
    print('no')
")
if [ "$NO_PREEM_ARKADY" = "yes" ]; then
  echo "  ✓ preem and arkady removed from all critic chains"
  ((PASS++))
else
  echo "  ✗ preem or arkady still in critic chains"
  ((FAIL++))
fi

# 6. VETO agents defined
VETO_DEFINED=$(python3 -c "
import json
with open('config/critic-chains.json') as f:
    cc = json.load(f)
veto = cc.get('veto_agents', {})
if 'hardin' in veto and 'gaal' in veto:
    print('yes')
else:
    print('no')
")
if [ "$VETO_DEFINED" = "yes" ]; then
  echo "  ✓ VETO agents defined: hardin (security), gaal (factual)"
  ((PASS++))
else
  echo "  ✗ VETO agents not properly defined"
  ((FAIL++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "=== PASS ==="
else
  echo "=== FAIL ==="
  exit 1
fi
