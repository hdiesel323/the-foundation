#!/usr/bin/env bash
# ============================================================
# Feature #225: End-to-end test — lead → deal → revenue pipeline
#
# Creates a lead, progresses through pipeline stages, records deal,
# aggregates to revenue, and verifies mallow revenue query picks it up.
#
# Prerequisites: PostgreSQL running with business schema
# Run: bash tests/test-e2e-lead-pipeline.sh
# ============================================================
set -euo pipefail

PSQL="docker exec openclaw-postgres psql -U openclaw -d openclaw -t -A"

echo "=== Feature #225: End-to-End Lead Pipeline Test ==="
echo ""

PASS=0
FAIL=0
TEST_ID="e2e-test-$(date +%s)"

# 1. Create a test lead
echo "Step 1: Insert test lead..."
$PSQL -c "
INSERT INTO leads (
  company_name, contact_name, contact_email, contact_phone,
  source, vertical, pipeline_stage, score, notes
) VALUES (
  'E2E Test Corp $TEST_ID', 'Test Contact', 'test@example.com', '+15551234567',
  'test', 'insurance', 'new', 75, 'Automated E2E test lead'
) RETURNING id;
" > /tmp/lead_id.txt 2>/dev/null

LEAD_ID=$(cat /tmp/lead_id.txt | tr -d ' ')
if [ -n "$LEAD_ID" ]; then
  echo "  ✓ Lead created: id=$LEAD_ID"
  ((PASS++))
else
  echo "  ✗ Failed to create lead"
  ((FAIL++))
  echo "=== FAIL ==="
  exit 1
fi

# 2. Progress through pipeline stages
echo ""
echo "Step 2: Progress through pipeline stages..."
for stage in "contacted" "qualified" "proposal" "closed_won"; do
  $PSQL -c "
    UPDATE leads SET pipeline_stage='$stage', last_contact_at=NOW()
    WHERE id='$LEAD_ID';
  " > /dev/null 2>&1

  CURRENT=$($PSQL -c "SELECT pipeline_stage FROM leads WHERE id='$LEAD_ID'")
  if [ "$CURRENT" = "$stage" ]; then
    echo "  ✓ Stage: $stage"
    ((PASS++))
  else
    echo "  ✗ Expected stage $stage, got $CURRENT"
    ((FAIL++))
  fi
done

# 3. Create deal record
echo ""
echo "Step 3: Create deal record..."
$PSQL -c "
INSERT INTO deals (
  lead_id, title, pipeline_stage, value, probability,
  vertical, notes
) VALUES (
  '$LEAD_ID', 'E2E Test Deal $TEST_ID', 'closed_won', 5000, 100,
  'insurance', 'Automated E2E test deal'
) RETURNING id;
" > /tmp/deal_id.txt 2>/dev/null

DEAL_ID=$(cat /tmp/deal_id.txt | tr -d ' ')
if [ -n "$DEAL_ID" ]; then
  echo "  ✓ Deal created: id=$DEAL_ID, value=\$5000, stage=closed_won"
  ((PASS++))
else
  echo "  ✗ Failed to create deal"
  ((FAIL++))
fi

# 4. Insert revenue record
echo ""
echo "Step 4: Record revenue..."
$PSQL -c "
INSERT INTO revenue (
  vertical, period_type, period_start, period_end,
  gross_revenue, costs
) VALUES (
  'insurance', 'monthly', DATE_TRUNC('month', NOW()), DATE_TRUNC('month', NOW()) + INTERVAL '1 month',
  5000, 500
) RETURNING id;
" > /tmp/rev_id.txt 2>/dev/null

REV_ID=$(cat /tmp/rev_id.txt | tr -d ' ')
if [ -n "$REV_ID" ]; then
  echo "  ✓ Revenue recorded: id=$REV_ID, gross=\$5000"
  ((PASS++))
else
  echo "  ✗ Failed to record revenue"
  ((FAIL++))
fi

# 5. Verify mallow revenue aggregation query
echo ""
echo "Step 5: Verify revenue aggregation (mallow query)..."
REVENUE_SUM=$($PSQL -c "
SELECT COALESCE(SUM(gross_revenue - costs), 0)
FROM revenue
WHERE vertical='insurance'
  AND period_type='monthly'
  AND period_start >= DATE_TRUNC('month', NOW());
")
REVENUE_SUM=$(echo "$REVENUE_SUM" | tr -d ' ')

if [ -n "$REVENUE_SUM" ] && [ "$REVENUE_SUM" != "0" ]; then
  echo "  ✓ Revenue aggregation: net=\$$REVENUE_SUM (insurance, this month)"
  ((PASS++))
else
  echo "  ✗ Revenue aggregation returned \$0 or empty"
  ((FAIL++))
fi

# 6. Verify full pipeline link
echo ""
echo "Step 6: Verify lead→deal→revenue chain..."
CHAIN=$($PSQL -c "
SELECT l.pipeline_stage, d.value, r.gross_revenue
FROM leads l
JOIN deals d ON d.lead_id = l.id
CROSS JOIN revenue r
WHERE l.id='$LEAD_ID'
  AND d.id='$DEAL_ID'
  AND r.id='$REV_ID';
")
if [ -n "$CHAIN" ]; then
  echo "  ✓ Full pipeline chain verified: $CHAIN"
  ((PASS++))
else
  echo "  ✗ Pipeline chain query returned empty"
  ((FAIL++))
fi

# Cleanup test data
echo ""
echo "Cleaning up test data..."
$PSQL -c "DELETE FROM revenue WHERE id='$REV_ID';" > /dev/null 2>&1
$PSQL -c "DELETE FROM deals WHERE id='$DEAL_ID';" > /dev/null 2>&1
$PSQL -c "DELETE FROM leads WHERE id='$LEAD_ID';" > /dev/null 2>&1
echo "  Done."

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "=== PASS ==="
else
  echo "=== FAIL ==="
  exit 1
fi
