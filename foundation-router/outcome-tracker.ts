/**
 * Outcome Tracker — Records routing decisions and computes per-agent success multipliers.
 *
 * Feeds back into the Foundation Router scoring engine via outcomeMultiplier (0.7x–1.3x).
 * Requires minimum 5 decisions before using multiplier (returns 1.0 before threshold).
 * Maintains a rolling window of 5000 records with debounced saves.
 */

import { Pool } from 'pg';

// ── Types ──────────────────────────────────────────────────────────────

export interface RoutingDecision {
  messageId: string;
  agentId: string;
  score: number;
  outcome: 'success' | 'failure';
  responseTimeMs: number;
  recordedAt: Date;
}

export interface AgentMultiplier {
  agentId: string;
  multiplier: number;
  totalDecisions: number;
  successCount: number;
  failureCount: number;
  successRate: number;
}

// ── Configuration ──────────────────────────────────────────────────────

const MIN_DECISIONS_FOR_MULTIPLIER = 5;
const MULTIPLIER_MIN = 0.7;
const MULTIPLIER_MAX = 1.3;
const ROLLING_WINDOW_SIZE = 5000;
const DEBOUNCE_SAVE_MS = parseInt(process.env.OUTCOME_SAVE_INTERVAL_MS ?? '10000', 10);

// ── State ──────────────────────────────────────────────────────────────

/** In-memory rolling window of recent routing decisions. */
const decisions: RoutingDecision[] = [];

/** Debounce timer for saving to PostgreSQL. */
let saveTimer: ReturnType<typeof setTimeout> | null = null;

// ── Database ───────────────────────────────────────────────────────────

const pool = new Pool({
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5434', 10),
  database: process.env.DB_NAME ?? 'openclaw',
  user: process.env.DB_USER ?? 'openclaw',
  password: process.env.DB_PASSWORD ?? 'openclaw',
});

// ── Core Functions ─────────────────────────────────────────────────────

/**
 * Record a routing decision and its outcome.
 * Maintains a rolling window of ROLLING_WINDOW_SIZE records.
 * Triggers a debounced save to PostgreSQL.
 */
export function recordDecision(decision: RoutingDecision): void {
  decisions.push(decision);

  // Enforce rolling window
  if (decisions.length > ROLLING_WINDOW_SIZE) {
    decisions.splice(0, decisions.length - ROLLING_WINDOW_SIZE);
  }

  // Debounced save to PostgreSQL
  scheduleSave();
}

/**
 * Compute the outcome multiplier for a specific agent.
 * Returns 1.0 if fewer than MIN_DECISIONS_FOR_MULTIPLIER decisions exist.
 * Range: MULTIPLIER_MIN (0.7) to MULTIPLIER_MAX (1.3).
 *
 * Multiplier formula:
 *   baseMultiplier = 0.7 + (successRate * 0.6)
 *   At 50% success → 1.0x (neutral)
 *   At 100% success → 1.3x (maximum boost)
 *   At 0% success → 0.7x (maximum dampening)
 */
export function getMultiplier(agentId: string): AgentMultiplier {
  const agentDecisions = decisions.filter(d => d.agentId === agentId);
  const totalDecisions = agentDecisions.length;
  const successCount = agentDecisions.filter(d => d.outcome === 'success').length;
  const failureCount = totalDecisions - successCount;
  const successRate = totalDecisions > 0 ? successCount / totalDecisions : 0;

  let multiplier = 1.0;
  if (totalDecisions >= MIN_DECISIONS_FOR_MULTIPLIER) {
    // Linear interpolation: 0% success → 0.7, 100% success → 1.3
    multiplier = MULTIPLIER_MIN + (successRate * (MULTIPLIER_MAX - MULTIPLIER_MIN));
    multiplier = Math.max(MULTIPLIER_MIN, Math.min(MULTIPLIER_MAX, multiplier));
  }

  return {
    agentId,
    multiplier,
    totalDecisions,
    successCount,
    failureCount,
    successRate,
  };
}

/**
 * Get multipliers for all agents that have recorded decisions.
 */
export function getAllMultipliers(): AgentMultiplier[] {
  const agentIds = new Set(decisions.map(d => d.agentId));
  return Array.from(agentIds).map(id => getMultiplier(id));
}

// ── Persistence ────────────────────────────────────────────────────────

/**
 * Schedule a debounced save to PostgreSQL.
 */
function scheduleSave(): void {
  if (saveTimer) return;
  saveTimer = setTimeout(async () => {
    saveTimer = null;
    await savePendingDecisions();
  }, DEBOUNCE_SAVE_MS);
}

/**
 * Save unsaved decisions to the routing_decisions table in PostgreSQL.
 * Inserts only decisions recorded since the last save.
 */
let lastSaveIndex = 0;

async function savePendingDecisions(): Promise<void> {
  const pending = decisions.slice(lastSaveIndex);
  if (pending.length === 0) return;

  try {
    const client = await pool.connect();
    try {
      for (const d of pending) {
        await client.query(
          `INSERT INTO metrics (metric_name, metric_value, labels, recorded_at)
           VALUES ('routing_decision', $1, $2, $3)
           ON CONFLICT DO NOTHING`,
          [
            d.score,
            JSON.stringify({
              message_id: d.messageId,
              agent_id: d.agentId,
              outcome: d.outcome,
              response_time_ms: d.responseTimeMs,
            }),
            d.recordedAt,
          ]
        );
      }
      lastSaveIndex = decisions.length;
      console.log(`[outcome-tracker] Saved ${pending.length} decisions to PostgreSQL`);
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[outcome-tracker] Save error:', err);
  }
}

/**
 * Load historical decisions from PostgreSQL to seed the in-memory window.
 */
export async function loadFromDatabase(): Promise<number> {
  try {
    const result = await pool.query(
      `SELECT metric_value, labels, recorded_at
       FROM metrics
       WHERE metric_name = 'routing_decision'
       ORDER BY recorded_at DESC
       LIMIT $1`,
      [ROLLING_WINDOW_SIZE]
    );

    for (const row of result.rows.reverse()) {
      const labels = row.labels as Record<string, unknown>;
      decisions.push({
        messageId: labels.message_id as string,
        agentId: labels.agent_id as string,
        score: parseFloat(String(row.metric_value)),
        outcome: labels.outcome as 'success' | 'failure',
        responseTimeMs: labels.response_time_ms as number,
        recordedAt: new Date(row.recorded_at),
      });
    }

    lastSaveIndex = decisions.length;
    console.log(`[outcome-tracker] Loaded ${result.rows.length} historical decisions`);
    return result.rows.length;
  } catch (err) {
    console.error('[outcome-tracker] Load error:', err);
    return 0;
  }
}

// ── Exports ────────────────────────────────────────────────────────────

export { decisions, ROLLING_WINDOW_SIZE, MIN_DECISIONS_FOR_MULTIPLIER, MULTIPLIER_MIN, MULTIPLIER_MAX };
