/**
 * Convex Bridge — Polls for unrouted messages and applies the scoring engine.
 *
 * Polls the messages table for entries without a routed agent (metadata->>'routed_to' IS NULL).
 * Runs the Foundation Router scoring engine on each unrouted message.
 * Routes to the best agent if score exceeds threshold, or falls back to Seldon (orchestrator).
 * Tracks processed message IDs to prevent re-routing.
 */

import { Pool } from 'pg';
import { routeMessage } from './scoring-engine.js';
import { agentProfiles } from './agent-profiles.js';
import type { RoutingResult } from './scoring-engine.js';

// ── Configuration ──────────────────────────────────────────────────────

const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS ?? '5000', 10);
const SCORE_THRESHOLD = parseFloat(process.env.SCORE_THRESHOLD ?? '0.15');
const FALLBACK_AGENT = 'seldon';
const BATCH_SIZE = 10;

// ── State ──────────────────────────────────────────────────────────────

/** Set of processed message IDs to prevent re-routing. */
const processedMessageIds = new Set<string>();

/** Maximum number of IDs to track before pruning oldest entries. */
const MAX_PROCESSED_IDS = 10000;

// ── Database ───────────────────────────────────────────────────────────

const pool = new Pool({
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5434', 10),
  database: process.env.DB_NAME ?? 'openclaw',
  user: process.env.DB_USER ?? 'openclaw',
  password: process.env.DB_PASSWORD ?? 'openclaw',
});

// ── Polling Logic ──────────────────────────────────────────────────────

/**
 * Fetch unrouted messages — messages without a 'to' field (metadata->>'routed_to' IS NULL).
 */
async function fetchUnroutedMessages(): Promise<Array<{ id: string; content: string; metadata: Record<string, unknown> }>> {
  const result = await pool.query(
    `SELECT id, content, metadata
     FROM messages
     WHERE (metadata->>'routed_to') IS NULL
       AND (metadata->>'routing_failed') IS NULL
     ORDER BY created_at ASC
     LIMIT $1`,
    [BATCH_SIZE]
  );
  return result.rows;
}

/**
 * Mark a message as routed to a specific agent.
 */
async function markMessageRouted(messageId: string, agentId: string, score: number): Promise<void> {
  await pool.query(
    `UPDATE messages
     SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
       'routed_to', $2,
       'routing_score', $3,
       'routed_at', NOW()::text
     )
     WHERE id = $1`,
    [messageId, agentId, score]
  );
}

/**
 * Mark a message as routing-failed (low confidence, sent to fallback).
 */
async function markMessageFallback(messageId: string, score: number): Promise<void> {
  await pool.query(
    `UPDATE messages
     SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
       'routed_to', $2,
       'routing_score', $3,
       'routing_fallback', true,
       'routed_at', NOW()::text
     )
     WHERE id = $1`,
    [messageId, FALLBACK_AGENT, score]
  );
}

// ── Core Routing ───────────────────────────────────────────────────────

/**
 * Process a single unrouted message through the scoring engine.
 */
async function processMessage(message: { id: string; content: string; metadata: Record<string, unknown> }): Promise<void> {
  // Skip already-processed messages
  if (processedMessageIds.has(message.id)) return;

  const routingResult: RoutingResult = routeMessage(
    { text: message.content },
    agentProfiles
  );

  if (routingResult.bestAgent && routingResult.bestAgent.finalScore >= SCORE_THRESHOLD) {
    // Route to best agent
    await markMessageRouted(message.id, routingResult.bestAgent.agentId, routingResult.bestAgent.finalScore);
    console.log(`[route] message=${message.id} -> agent=${routingResult.bestAgent.agentId} score=${routingResult.bestAgent.finalScore.toFixed(3)}`);
  } else {
    // Low confidence — fallback to Seldon (orchestrator)
    const score = routingResult.bestAgent?.finalScore ?? 0;
    await markMessageFallback(message.id, score);
    console.log(`[fallback] message=${message.id} -> agent=${FALLBACK_AGENT} score=${score.toFixed(3)} (below threshold ${SCORE_THRESHOLD})`);
  }

  // Track processed ID
  processedMessageIds.add(message.id);

  // Prune if too many tracked IDs
  if (processedMessageIds.size > MAX_PROCESSED_IDS) {
    const iterator = processedMessageIds.values();
    for (let i = 0; i < MAX_PROCESSED_IDS / 2; i++) {
      const val = iterator.next();
      if (val.done) break;
      processedMessageIds.delete(val.value);
    }
  }
}

// ── Poll Loop ──────────────────────────────────────────────────────────

/**
 * Single poll iteration: fetch unrouted messages and process them.
 */
async function pollOnce(): Promise<number> {
  const messages = await fetchUnroutedMessages();
  let processed = 0;

  for (const msg of messages) {
    if (!processedMessageIds.has(msg.id)) {
      await processMessage(msg);
      processed++;
    }
  }

  return processed;
}

/**
 * Start the polling loop. Runs until the process is terminated.
 */
async function startPolling(): Promise<void> {
  console.log(`[convex-bridge] Starting polling loop (interval=${POLL_INTERVAL_MS}ms, threshold=${SCORE_THRESHOLD}, fallback=${FALLBACK_AGENT})`);

  const poll = async () => {
    try {
      const count = await pollOnce();
      if (count > 0) {
        console.log(`[convex-bridge] Processed ${count} messages`);
      }
    } catch (err) {
      console.error('[convex-bridge] Poll error:', err);
    }
  };

  // Initial poll
  await poll();

  // Repeat on interval
  setInterval(poll, POLL_INTERVAL_MS);
}

// ── Exports ────────────────────────────────────────────────────────────

export { fetchUnroutedMessages, processMessage, pollOnce, startPolling, processedMessageIds };

// ── Main ───────────────────────────────────────────────────────────────

// Start polling if run directly
const isMain = process.argv[1]?.endsWith('convex-bridge.ts') || process.argv[1]?.endsWith('convex-bridge.js');
if (isMain) {
  startPolling().catch(err => {
    console.error('[convex-bridge] Fatal error:', err);
    process.exit(1);
  });
}
