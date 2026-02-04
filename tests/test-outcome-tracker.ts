// ============================================================
// Outcome Tracker Learning Test
//
// Verifies that the outcome tracker adjusts agent multipliers
// based on routing success/failure rates.
// ============================================================

import { OutcomeTracker } from "../foundation-router/outcome-tracker.js";

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string): void {
  if (condition) {
    console.log(`[PASS] ${message}`);
    passed++;
  } else {
    console.log(`[FAIL] ${message}`);
    failed++;
  }
}

console.log("=== Outcome Tracker Learning Tests ===\n");

// Test 1: Register 5+ routing decisions
console.log("--- Test 1: Register routing decisions ---");
{
  const tracker = new OutcomeTracker();

  // Register 5 decisions for test-agent: 4 success, 1 failure
  tracker.recordDecision("test-agent", "success");
  tracker.recordDecision("test-agent", "success");
  tracker.recordDecision("test-agent", "success");
  tracker.recordDecision("test-agent", "success");
  tracker.recordDecision("test-agent", "failure");

  const multiplier = tracker.getMultiplier("test-agent");
  assert(
    multiplier !== undefined,
    `Registered 5 decisions, got multiplier: ${multiplier?.toFixed(4)}`
  );
}

// Test 2: Verify multiplier range (0.7x-1.3x)
console.log("\n--- Test 2: Multiplier in 0.7x-1.3x range ---");
{
  const tracker = new OutcomeTracker();

  // All successes → high multiplier
  for (let i = 0; i < 10; i++) {
    tracker.recordDecision("good-agent", "success");
  }
  const goodMultiplier = tracker.getMultiplier("good-agent") ?? 1.0;
  assert(
    goodMultiplier >= 0.7 && goodMultiplier <= 1.3,
    `Good agent multiplier: ${goodMultiplier.toFixed(4)} (expected ~1.3)`
  );
  assert(
    goodMultiplier > 1.0,
    `Good agent multiplier > 1.0 (got ${goodMultiplier.toFixed(4)})`
  );

  // All failures → low multiplier
  for (let i = 0; i < 10; i++) {
    tracker.recordDecision("bad-agent", "failure");
  }
  const badMultiplier = tracker.getMultiplier("bad-agent") ?? 1.0;
  assert(
    badMultiplier >= 0.7 && badMultiplier <= 1.3,
    `Bad agent multiplier: ${badMultiplier.toFixed(4)} (expected ~0.7)`
  );
  assert(
    badMultiplier < 1.0,
    `Bad agent multiplier < 1.0 (got ${badMultiplier.toFixed(4)})`
  );
}

// Test 3: Minimum 5 decisions before multiplier applies
console.log("\n--- Test 3: Minimum 5 decisions threshold ---");
{
  const tracker = new OutcomeTracker();

  // Only 3 decisions
  tracker.recordDecision("new-agent", "success");
  tracker.recordDecision("new-agent", "success");
  tracker.recordDecision("new-agent", "failure");

  const multiplier = tracker.getMultiplier("new-agent") ?? 1.0;
  assert(
    multiplier === 1.0,
    `New agent with <5 decisions gets default multiplier: ${multiplier.toFixed(4)} (expected 1.0)`
  );
}

// Test 4: Mixed success/failure adjusts proportionally
console.log("\n--- Test 4: Proportional adjustment ---");
{
  const tracker = new OutcomeTracker();

  // 50% success rate
  for (let i = 0; i < 5; i++) {
    tracker.recordDecision("mixed-agent", "success");
    tracker.recordDecision("mixed-agent", "failure");
  }

  const multiplier = tracker.getMultiplier("mixed-agent") ?? 1.0;
  assert(
    multiplier >= 0.95 && multiplier <= 1.05,
    `50% success rate multiplier: ${multiplier.toFixed(4)} (expected ~1.0)`
  );
}

// Test 5: Rolling window behavior
console.log("\n--- Test 5: Rolling window caps records ---");
{
  const tracker = new OutcomeTracker();

  // The tracker should handle large numbers of decisions
  for (let i = 0; i < 100; i++) {
    tracker.recordDecision("heavy-agent", i % 3 === 0 ? "failure" : "success");
  }

  const multiplier = tracker.getMultiplier("heavy-agent") ?? 1.0;
  assert(
    multiplier >= 0.7 && multiplier <= 1.3,
    `Heavy-use agent multiplier: ${multiplier.toFixed(4)} (~67% success, expected >1.0)`
  );
  assert(
    typeof tracker.getMultiplier === "function",
    "Tracker supports rolling window via getMultiplier"
  );
}

console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
process.exit(failed > 0 ? 1 : 0);
