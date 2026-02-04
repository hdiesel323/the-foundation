/**
 * Demerzel Patrol — 2-hourly cross-division intelligence synthesis.
 *
 * Synthesizes: agent disposition, division coverage, task intelligence,
 * project intelligence. Performs threat assessment and opportunity reporting.
 * Correlates hot projects + blocked tasks for systemic issues.
 */

import { Pool } from 'pg';
import type { PatrolFinding } from '../base-runner.js';

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
 * Agent disposition: status of all agents across the fleet.
 */
export async function synthesizeAgentDisposition(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT status, COUNT(*) AS count FROM agents GROUP BY status ORDER BY count DESC`
    );

    const statusMap: Record<string, number> = {};
    for (const row of result.rows) {
      statusMap[String(row.status)] = parseInt(String(row.count), 10);
    }

    const total = Object.values(statusMap).reduce((s, c) => s + c, 0);
    const online = (statusMap['online'] ?? 0) + (statusMap['healthy'] ?? 0) + (statusMap['busy'] ?? 0);
    const offline = statusMap['offline'] ?? 0;
    const errored = (statusMap['error'] ?? 0) + (statusMap['dead'] ?? 0);

    findings.push({
      subject: 'fleet',
      predicate: 'disposition',
      description: `Fleet disposition: ${online}/${total} online, ${offline} offline, ${errored} errored`,
      severity: errored > 0 ? 'warning' : 'info',
    });

    if (online < total * 0.5) {
      findings.push({
        subject: 'fleet',
        predicate: 'low_availability',
        description: `Less than 50% of agents online (${online}/${total}). Fleet degraded.`,
        severity: 'critical',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'fleet',
      predicate: 'disposition_failed',
      description: `Agent disposition check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Division coverage: which divisions have active agents and which don't.
 */
export async function synthesizeDivisionCoverage(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT
         COALESCE(metadata->>'division', 'unknown') AS division,
         COUNT(*) FILTER (WHERE status IN ('online', 'healthy', 'busy')) AS active,
         COUNT(*) AS total
       FROM agents
       GROUP BY division
       ORDER BY division`
    );

    const divisions = result.rows.map(r => ({
      division: String(r.division),
      active: parseInt(String(r.active), 10),
      total: parseInt(String(r.total), 10),
    }));

    const underCovered = divisions.filter(d => d.active === 0 && d.total > 0);
    if (underCovered.length > 0) {
      findings.push({
        subject: 'divisions',
        predicate: 'coverage_gaps',
        description: `Division coverage gaps: ${underCovered.map(d => d.division).join(', ')} have no active agents`,
        severity: 'warning',
      });
    }

    findings.push({
      subject: 'divisions',
      predicate: 'coverage_summary',
      description: `Division coverage: ${divisions.map(d => `${d.division}=${d.active}/${d.total}`).join(', ')}`,
      severity: 'info',
    });
  } catch (err) {
    findings.push({
      subject: 'divisions',
      predicate: 'coverage_failed',
      description: `Division coverage synthesis failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Task intelligence: task flow, completion rates, bottlenecks.
 */
export async function synthesizeTaskIntelligence(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    const result = await pool.query(
      `SELECT status, COUNT(*) AS count FROM tasks GROUP BY status`
    );

    const statusMap: Record<string, number> = {};
    for (const row of result.rows) {
      statusMap[String(row.status)] = parseInt(String(row.count), 10);
    }

    const pending = statusMap['pending'] ?? 0;
    const inProgress = statusMap['in_progress'] ?? 0;
    const completed = statusMap['completed'] ?? 0;
    const failed = statusMap['failed'] ?? 0;
    const total = Object.values(statusMap).reduce((s, c) => s + c, 0);

    findings.push({
      subject: 'tasks',
      predicate: 'intelligence',
      description: `Task intelligence: ${total} total (${pending} pending, ${inProgress} in-progress, ${completed} completed, ${failed} failed)`,
      severity: failed > 5 ? 'warning' : 'info',
    });

    // Check for task pile-up
    if (pending > 20) {
      findings.push({
        subject: 'tasks',
        predicate: 'pile_up',
        description: `Task pile-up: ${pending} pending tasks awaiting processing`,
        severity: 'warning',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'tasks',
      predicate: 'intelligence_failed',
      description: `Task intelligence synthesis failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Threat assessment: correlate hot projects with blocked tasks.
 * Hot tasks (in_progress >30min) + blocked agents → systemic issue.
 */
export async function assessThreats(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    // Hot tasks: in_progress for over 30 minutes
    const hotResult = await pool.query(
      `SELECT t.id, t.name, t.agent_id,
              EXTRACT(EPOCH FROM (NOW() - t.started_at)) AS duration_s
       FROM tasks t
       WHERE t.status = 'in_progress'
         AND t.started_at < NOW() - INTERVAL '30 minutes'
       ORDER BY t.started_at ASC`
    );

    // Blocked tasks: pending for over 1 hour
    const blockedResult = await pool.query(
      `SELECT t.id, t.name, t.agent_id,
              EXTRACT(EPOCH FROM (NOW() - t.created_at)) AS wait_s
       FROM tasks t
       WHERE t.status = 'pending'
         AND t.created_at < NOW() - INTERVAL '1 hour'
       ORDER BY t.created_at ASC`
    );

    const hotTasks = hotResult.rows;
    const blockedTasks = blockedResult.rows;

    // Correlate: if hot tasks and blocked tasks involve the same agent → bottleneck
    if (hotTasks.length > 0 && blockedTasks.length > 0) {
      const hotAgents = new Set(hotTasks.map(t => String(t.agent_id)));
      const blockedAgents = new Set(blockedTasks.map(t => String(t.agent_id)));
      const overlap = [...hotAgents].filter(a => blockedAgents.has(a));

      if (overlap.length > 0) {
        findings.push({
          subject: 'threat',
          predicate: 'agent_bottleneck',
          description: `Bottleneck: agents [${overlap.join(', ')}] have both hot and blocked tasks. Possible resource contention.`,
          severity: 'critical',
        });
      }

      findings.push({
        subject: 'threat',
        predicate: 'systemic_risk',
        description: `Systemic risk: ${hotTasks.length} hot task(s) + ${blockedTasks.length} blocked task(s) detected across fleet`,
        severity: 'warning',
      });
    }

    // Failed task rate as threat indicator
    const failedResult = await pool.query(
      `SELECT COUNT(*) AS count FROM tasks
       WHERE status = 'failed'
         AND updated_at > NOW() - INTERVAL '2 hours'`
    );
    const recentFailures = parseInt(String(failedResult.rows[0].count), 10);
    if (recentFailures > 5) {
      findings.push({
        subject: 'threat',
        predicate: 'high_failure_rate',
        description: `${recentFailures} task failures in last 2 hours. Elevated failure rate.`,
        severity: 'warning',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'threat',
      predicate: 'assessment_failed',
      description: `Threat assessment failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Opportunity reporting: detect underutilized agents and spare capacity.
 */
export async function reportOpportunities(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [];
  try {
    // Find online agents with no tasks in last 2 hours
    const result = await pool.query(
      `SELECT a.id, a.name, a.role
       FROM agents a
       WHERE a.status IN ('online', 'healthy')
         AND NOT EXISTS (
           SELECT 1 FROM tasks t
           WHERE t.agent_id = a.id
             AND t.created_at > NOW() - INTERVAL '2 hours'
         )`
    );

    if (result.rows.length > 0) {
      findings.push({
        subject: 'opportunity',
        predicate: 'idle_agents',
        description: `Idle agents (no tasks in 2h): ${result.rows.map(r => `${r.id} (${r.role})`).join(', ')}. Available for reallocation.`,
        severity: 'info',
      });
    }
  } catch (err) {
    findings.push({
      subject: 'opportunity',
      predicate: 'reporting_failed',
      description: `Opportunity reporting failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

/**
 * Run all demerzel patrol checks and return combined findings.
 * 2-hourly cross-division intelligence synthesis.
 */
export async function runDemerzelPatrol(): Promise<PatrolFinding[]> {
  const findings: PatrolFinding[] = [
    ...(await synthesizeAgentDisposition()),
    ...(await synthesizeDivisionCoverage()),
    ...(await synthesizeTaskIntelligence()),
    ...(await assessThreats()),
    ...(await reportOpportunities()),
  ];

  return findings;
}
