// ============================================================
// Foundation Router Integration Test
//
// Verifies that messages are routed to correct agents based on
// the 5-signal scoring algorithm.
// ============================================================

import { routeMessage } from "../foundation-router/scoring-engine.js";
import { agentProfiles } from "../foundation-router/agent-profiles.js";
import type { RoutingMessage } from "../foundation-router/scoring-engine.js";

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

function makeMessage(text: string, overrides?: Partial<RoutingMessage>): RoutingMessage {
  return {
    text,
    ...overrides,
  };
}

console.log("=== Foundation Router Routing Tests ===\n");

// Test 1: Security keywords route to hardin
console.log("--- Test 1: Security keywords → hardin ---");
{
  const msg = makeMessage(
    "We need to review the firewall rules and check for security vulnerabilities in the infrastructure"
  );
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.bestAgent?.agentId ?? "none";
  assert(
    topAgent === "hardin",
    `Security message routed to ${topAgent} (expected hardin)`
  );
  assert(
    result.allScores.length > 0,
    `Scoring produced ${result.allScores.length} scored agents`
  );
  const hardinScore = result.allScores.find((s) => s.agentId === "hardin");
  if (hardinScore) {
    console.log(`  Hardin score breakdown:`);
    console.log(`    Keyword: ${hardinScore.keywordScore.toFixed(4)}`);
    console.log(`    Intent: ${hardinScore.intentScore.toFixed(4)}`);
    console.log(`    Mention: ${hardinScore.mentionScore.toFixed(4)}`);
    console.log(`    Division: ${hardinScore.divisionScore.toFixed(4)}`);
    console.log(`    Final: ${hardinScore.finalScore.toFixed(4)}`);
  }
}

// Test 2: Research keywords route to gaal
console.log("\n--- Test 2: Research keywords → gaal ---");
{
  const msg = makeMessage(
    "I need research on the latest AI developments and summarize the key findings for analysis"
  );
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.bestAgent?.agentId ?? "none";
  assert(
    topAgent === "gaal",
    `Research message routed to ${topAgent} (expected gaal)`
  );
  const gaalScore = result.allScores.find((s) => s.agentId === "gaal");
  if (gaalScore) {
    console.log(`  Gaal score breakdown:`);
    console.log(`    Keyword: ${gaalScore.keywordScore.toFixed(4)}`);
    console.log(`    Intent: ${gaalScore.intentScore.toFixed(4)}`);
    console.log(`    Final: ${gaalScore.finalScore.toFixed(4)}`);
  }
}

// Test 3: Ambiguous message falls back to seldon
console.log("\n--- Test 3: Ambiguous message → seldon (fallback) ---");
{
  const msg = makeMessage("Hi, how's everything going today?");
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.bestAgent?.agentId ?? "seldon";
  const confidence = result.bestAgent?.finalScore ?? 0;
  assert(
    topAgent === "seldon" || confidence < 0.15,
    `Ambiguous message routed to ${topAgent} (expected seldon or low confidence)`
  );
}

// Test 4: Revenue keywords route to mallow
console.log("\n--- Test 4: Revenue keywords → mallow ---");
{
  const msg = makeMessage(
    "We need to send an invoice to the client for the consulting project and track the revenue"
  );
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.bestAgent?.agentId ?? "none";
  assert(
    topAgent === "mallow",
    `Revenue message routed to ${topAgent} (expected mallow)`
  );
}

// Test 5: Direct mention routes correctly
console.log("\n--- Test 5: Direct @mention → mentioned agent ---");
{
  const msg = makeMessage("@daneel can you check the server disk usage?");
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.bestAgent?.agentId ?? "none";
  assert(
    topAgent === "daneel",
    `@daneel mention routed to ${topAgent} (expected daneel)`
  );
}

// Test 6: Verify scoring breakdown has all 5 signals
console.log("\n--- Test 6: All 5 scoring signals present ---");
{
  const msg = makeMessage("Deploy the new database migration to production servers");
  const result = routeMessage(msg, agentProfiles);
  const topAgent = result.allScores[0];
  assert(
    topAgent !== undefined &&
    topAgent.keywordScore !== undefined &&
    topAgent.intentScore !== undefined &&
    topAgent.mentionScore !== undefined &&
    topAgent.divisionScore !== undefined &&
    topAgent.finalScore !== undefined,
    "Scoring breakdown includes all 5 signal weights"
  );
  if (topAgent) {
    console.log(`  Top agent: ${topAgent.agentId}`);
    console.log(`    keywordScore:  ${topAgent.keywordScore.toFixed(4)} (weight: 0.4)`);
    console.log(`    intentScore:   ${topAgent.intentScore.toFixed(4)} (weight: 0.3)`);
    console.log(`    mentionScore:  ${topAgent.mentionScore.toFixed(4)} (weight: 0.2)`);
    console.log(`    divisionScore: ${topAgent.divisionScore.toFixed(4)} (weight: 0.1)`);
    console.log(`    finalScore:    ${topAgent.finalScore.toFixed(4)}`);
  }
}

console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
process.exit(failed > 0 ? 1 : 0);
