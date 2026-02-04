/**
 * Hardin Patrol — Hourly security and fleet health checks.
 *
 * Checks: stale agents (>2min heartbeat gap), agent error states,
 * hot+stalled project correlation (systemic blockage), division coverage
 * (all divisions have at least one active agent).
 * Publishes security insights with 600s TTL to shared memory.
 */

import { Pool } from 'pg';
import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const STALE_AGENT_THRESHOLD_MS = 2 * 60 * 1000; // 2 minutes
const INSIGHT_TTL_SECONDS = 600; // 10 minutes

const REQUIRED_DIVISIONS = ['command', 'infrastructure', 'commerce', 'intelligence', 'operations'];

// ── Database ───────────────────────────────────────────────────────────

const pool = new Pool({
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5434', 10),
  database: process.env.DB_NAME ?? 'openclaw',
  user: process.env.DB_USER ?? 'openclaw',
  password: process.env.DB_PASSWORD ?? 'openclaw',
});

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Check for stale agents — agents whose last heartbeat is older than 2 minutes.
 */
export async function checkStaleAgents(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT id, name, role, status, last_heartbeat,
              EXTRACT(EPOCH FROM (NOW() - last_heartbeat)) * 1000 AS gap_ms
       FROM agents
       WHERE status != 'offline'
         AND last_heartbeat IS NOT NULL
         AND last_heartbeat < NOW() - INTERVAL '2 minutes'`
    );

    for (const row of result.rows) {
      const gapMs = parseFloat(String(row.gap_ms));
      findings.push({
        subject: `agent:${row.id}`,
        predicate: 'stale_heartbeat',
        description: `Agent ${row.id} (${row.role}) last heartbeat ${Math.round(gapMs / 1000)}s ago (threshold: ${STALE_AGENT_THRESHOLD_MS / 1000}s). Status: ${row.status}`,
        severity: gapMs > STALE_AGENT_THRESHOLD_MS * 3 ? 'critical' : 'warning',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'agents',
      predicate: 'stale_check_failed',
      description: `Stale agent check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Check for agents in error states (status = 'error' or 'dead').
 */
export async function checkAgentErrorStates(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT id, name, role, status, last_heartbeat
       FROM agents
       WHERE status IN ('error', 'dead', 'unhealthy')`
    );

    for (const row of result.rows) {
      findings.push({
        subject: `agent:${row.id}`,
        predicate: 'error_state',
        description: `Agent ${row.id} (${row.role}) is in ${row.status} state`,
        severity: 'critical',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'agents',
      predicate: 'error_check_failed',
      description: `Agent error state check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Detect systemic blockage: hot tasks (high activity) + stalled tasks (no progress)
 * happening simultaneously suggests a systemic issue.
 */
export async function checkSystemicBlockage(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    // Count hot tasks (in_progress for >30 minutes)
    const hotResult = await pool.query(
      `SELECT COUNT(*) AS count FROM tasks
       WHERE status = 'in_progress'
         AND started_at < NOW() - INTERVAL '30 minutes'`
    );
    const hotCount = parseInt(String(hotResult.rows[0].count), 10);

    // Count stalled tasks (pending for >1 hour)
    const stalledResult = await pool.query(
      `SELECT COUNT(*) AS count FROM tasks
       WHERE status = 'pending'
         AND created_at < NOW() - INTERVAL '1 hour'`
    );
    const stalledCount = parseInt(String(stalledResult.rows[0].count), 10);

    // Correlation: if both hot AND stalled tasks exist, likely systemic
    if (hotCount > 0 && stalledCount > 0) {
      findings.push({
        subject: 'system',
        predicate: 'blockage_detected',
        description: `Systemic blockage: ${hotCount} task(s) running >30min + ${stalledCount} task(s) pending >1hr. Possible bottleneck or resource contention.`,
        severity: 'critical',
      });
    } else if (stalledCount > 3) {
      findings.push({
        subject: 'system',
        predicate: 'stalled_tasks',
        description: `${stalledCount} task(s) pending >1hr without being claimed`,
        severity: 'warning',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'system',
      predicate: 'blockage_check_failed',
      description: `Systemic blockage check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Verify all divisions have at least one active (online/healthy) agent.
 */
export async function checkDivisionCoverage(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT DISTINCT
         COALESCE(metadata->>'division', 'unknown') AS division
       FROM agents
       WHERE status IN ('online', 'healthy', 'busy')`
    );

    const activeDivisions = new Set(result.rows.map(r => String(r.division)));

    for (const division of REQUIRED_DIVISIONS) {
      if (!activeDivisions.has(division)) {
        findings.push({
          subject: `division:${division}`,
          predicate: 'no_active_agents',
          description: `Division '${division}' has no active agents. Coverage gap detected.`,
          severity: 'warning',
        });
      }
    }
  } catch (err) {
    findings.push({
      subject: 'divisions',
      predicate: 'coverage_check_failed',
      description: `Division coverage check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

/**
 * Run all hardin patrol checks and return combined findings.
 * Findings carry TTL metadata for 600s (10 minutes) expiry.
 * Intended to be called from BaseRunner.runPatrol() override.
 */
export async function runHardinPatrol(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [
    ...(await checkStaleAgents()),
    ...(await checkAgentErrorStates()),
    ...(await checkSystemicBlockage()),
    ...(await checkDivisionCoverage()),
  ];

  // Tag all findings with TTL for shared memory publishing
  for (const f of findings) {
    f.description += ` [TTL: ${INSIGHT_TTL_SECONDS}s]`;
  }

  return findings;
}

export { INSIGHT_TTL_SECONDS };
