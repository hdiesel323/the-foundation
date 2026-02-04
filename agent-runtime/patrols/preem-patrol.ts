/**
 * Preem Patrol — 4-hourly pipeline health check.
 *
 * Scans for: stale leads (no contact >7 days), overdue follow-ups,
 * deals at risk (no activity >3 days), and pipeline velocity anomalies.
 * Dispatches alerts via Seldon for urgent items.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const STALE_LEAD_DAYS = 7;
const AT_RISK_DEAL_DAYS = 3;
const OVERDUE_FOLLOWUP_HOURS = 48;
const PIPELINE_VELOCITY_WARNING_DAYS = 21;

interface LeadRow {
  id: string;
  company_name: string;
  pipeline_stage: string;
  last_contact_at: string | null;
  created_at: string;
  score: number;
}

interface DealRow {
  id: string;
  title: string;
  pipeline_stage: string;
  last_activity_at: string | null;
  value: number;
  probability: number;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

function daysSince(dateStr: string | null): number {
  if (!dateStr) return Infinity;
  const diff = Date.now() - new Date(dateStr).getTime();
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}

/**
 * Check for stale leads — no contact in >7 days while still in active pipeline.
 */
export function checkStaleLeads(leads: LeadRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  const activeStages = ['new', 'contacted', 'qualified', 'proposal'];

  const stale = leads.filter(
    (l) => activeStages.includes(l.pipeline_stage) && daysSince(l.last_contact_at) > STALE_LEAD_DAYS
  );

  if (stale.length > 0) {
    findings.push({
      level: stale.length > 10 ? 'critical' : 'warning',
      source: 'preem-patrol',
      message: `${stale.length} stale leads with no contact in >${STALE_LEAD_DAYS} days`,
      detail: stale.slice(0, 10).map((l) => ({
        id: l.id,
        company: l.company_name,
        stage: l.pipeline_stage,
        days_stale: daysSince(l.last_contact_at),
        score: l.score,
      })),
      action: 'Prioritize re-engagement for high-score stale leads',
    });
  }

  return findings;
}

/**
 * Check for overdue follow-ups — leads that were contacted but not followed up.
 */
export function checkOverdueFollowups(leads: LeadRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  const followupStages = ['contacted', 'qualified'];

  const overdue = leads.filter(
    (l) =>
      followupStages.includes(l.pipeline_stage) &&
      l.last_contact_at &&
      daysSince(l.last_contact_at) > OVERDUE_FOLLOWUP_HOURS / 24
  );

  if (overdue.length > 0) {
    findings.push({
      level: 'warning',
      source: 'preem-patrol',
      message: `${overdue.length} leads with overdue follow-ups (>${OVERDUE_FOLLOWUP_HOURS}h)`,
      detail: overdue.slice(0, 10).map((l) => ({
        id: l.id,
        company: l.company_name,
        stage: l.pipeline_stage,
        hours_since_contact: daysSince(l.last_contact_at) * 24,
      })),
      action: 'Execute follow-up sequences for overdue leads',
    });
  }

  return findings;
}

/**
 * Check for deals at risk — no activity in >3 days on active deals.
 */
export function checkAtRiskDeals(deals: DealRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  const activeStages = ['discovery', 'proposal', 'negotiation', 'verbal_yes'];

  const atRisk = deals.filter(
    (d) => activeStages.includes(d.pipeline_stage) && daysSince(d.last_activity_at) > AT_RISK_DEAL_DAYS
  );

  if (atRisk.length > 0) {
    const totalValue = atRisk.reduce((sum, d) => sum + d.value, 0);
    findings.push({
      level: totalValue > 10000 ? 'critical' : 'warning',
      source: 'preem-patrol',
      message: `${atRisk.length} deals at risk ($${totalValue.toLocaleString()} total value) — no activity >${AT_RISK_DEAL_DAYS} days`,
      detail: atRisk.slice(0, 10).map((d) => ({
        id: d.id,
        title: d.title,
        stage: d.pipeline_stage,
        value: d.value,
        days_inactive: daysSince(d.last_activity_at),
      })),
      action: 'Re-engage deal contacts or escalate to Seldon',
    });
  }

  return findings;
}

/**
 * Check pipeline velocity — deals stuck too long in a stage.
 */
export function checkPipelineVelocity(deals: DealRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  const activeStages = ['discovery', 'proposal', 'negotiation'];

  const slow = deals.filter(
    (d) => activeStages.includes(d.pipeline_stage) && daysSince(d.last_activity_at) > PIPELINE_VELOCITY_WARNING_DAYS
  );

  if (slow.length > 0) {
    findings.push({
      level: 'info',
      source: 'preem-patrol',
      message: `${slow.length} deals exceeding ${PIPELINE_VELOCITY_WARNING_DAYS}-day velocity threshold`,
      detail: slow.map((d) => ({
        id: d.id,
        title: d.title,
        stage: d.pipeline_stage,
        days_in_stage: daysSince(d.last_activity_at),
      })),
      action: 'Review deal progression strategy or mark as lost',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'preem-pipeline-health',
  agent: 'preem',
  interval_hours: 4,
  description: 'Pipeline health check: stale leads, overdue follow-ups, at-risk deals',
  dispatch_to: 'seldon',
};
