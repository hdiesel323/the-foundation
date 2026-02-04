#!/usr/bin/env bash
# ============================================================
# Feature #219: Verify all 12 business tables create in PostgreSQL
#
# Prerequisites: docker compose services running
# Run: bash tests/test-business-schema.sh
# ============================================================
set -euo pipefail

PSQL="docker exec openclaw-postgres psql -U openclaw -d openclaw -t -A"

echo "=== Feature #219: Business Schema Verification ==="
echo ""

# Expected tables from 01-schema.sql and 02-business-schema.sql
EXPECTED_TABLES=(
  "leads"
  "deals"
  "outreach_log"
  "campaigns"
  "suppliers"
  "products"
  "revenue"
  "trading_positions"
  "competitors"
  "competitor_changes"
  "scan_history"
)

echo "Checking business tables..."
PASS=0
FAIL=0
for table in "${EXPECTED_TABLES[@]}"; do
  EXISTS=$($PSQL -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='$table')")
  if [ "$EXISTS" = "t" ]; then
    echo "  ✓ $table"
    ((PASS++))
  else
    echo "  ✗ $table — NOT FOUND"
    ((FAIL++))
  fi
done

# Also check for agents table from 01-schema.sql
CORE_EXISTS=$($PSQL -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='agents')")
if [ "$CORE_EXISTS" = "t" ]; then
  echo "  ✓ agents (core)"
  ((PASS++))
else
  echo "  ✗ agents (core) — NOT FOUND"
  ((FAIL++))
fi

# Count total indexes
INDEX_COUNT=$($PSQL -c "SELECT count(*) FROM pg_indexes WHERE schemaname='public'")
echo ""
echo "Total indexes: $INDEX_COUNT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "=== PASS ==="
else
  echo "=== FAIL ==="
  exit 1
fi
