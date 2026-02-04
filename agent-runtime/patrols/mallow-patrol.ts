/**
 * Mallow Patrol — Daily revenue aggregation and trend analysis.
 *
 * Aggregates revenue across all verticals (trading, ecommerce, lead_gen,
 * funding, CRE), computes forecast vs actual, identifies anomalies,
 * and generates daily/weekly/monthly summaries.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const MONTHLY_REVENUE_TARGET = 20000;
const WEEKLY_REVENUE_TARGET = 5000;
const ANOMALY_THRESHOLD_PCT = 25;

interface RevenueRow {
  vertical: string;
  period_type: string;
  period_start: string;
  gross_revenue: number;
  costs: number;
  net_revenue: number;
}

interface VerticalSummary {
  vertical: string;
  current_revenue: number;
  target: number;
  pct_of_target: number;
  trend: 'up' | 'down' | 'flat';
  wow_change_pct: number;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Aggregate revenue across all verticals and compare to targets.
 */
export function checkRevenueVsTarget(revenue: RevenueRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const monthlyByVertical = new Map<string, number>();
  for (const r of revenue) {
    if (r.period_type === 'monthly') {
      const curr = monthlyByVertical.get(r.vertical) || 0;
      monthlyByVertical.set(r.vertical, curr + r.net_revenue);
    }
  }

  const totalMonthly = Array.from(monthlyByVertical.values()).reduce((a, b) => a + b, 0);
  const pctOfTarget = (totalMonthly / MONTHLY_REVENUE_TARGET) * 100;

  // Calculate days into month for pace check
  const now = new Date();
  const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const dayOfMonth = now.getDate();
  const expectedPacePct = (dayOfMonth / daysInMonth) * 100;

  if (pctOfTarget < expectedPacePct * 0.8) {
    findings.push({
      level: 'critical',
      source: 'mallow-patrol',
      message: `Revenue behind pace: $${totalMonthly.toLocaleString()} (${pctOfTarget.toFixed(1)}% of $${MONTHLY_REVENUE_TARGET.toLocaleString()} target, expected ~${expectedPacePct.toFixed(0)}% by day ${dayOfMonth})`,
      detail: Array.from(monthlyByVertical.entries()).map(([v, r]) => ({
        vertical: v,
        revenue: r,
      })),
      action: 'Escalate to Seldon — revenue recovery plan needed',
    });
  } else if (pctOfTarget >= 100) {
    findings.push({
      level: 'info',
      source: 'mallow-patrol',
      message: `Monthly target exceeded: $${totalMonthly.toLocaleString()} (${pctOfTarget.toFixed(1)}%)`,
      detail: Array.from(monthlyByVertical.entries()).map(([v, r]) => ({
        vertical: v,
        revenue: r,
      })),
      action: 'Continue momentum — consider raising next month targets',
    });
  }

  return findings;
}

/**
 * Detect revenue anomalies — sudden drops or spikes vs prior period.
 */
export function checkRevenueAnomalies(
  currentWeek: RevenueRow[],
  priorWeek: RevenueRow[]
): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const currentByVertical = new Map<string, number>();
  const priorByVertical = new Map<string, number>();

  for (const r of currentWeek) {
    currentByVertical.set(r.vertical, (currentByVertical.get(r.vertical) || 0) + r.net_revenue);
  }
  for (const r of priorWeek) {
    priorByVertical.set(r.vertical, (priorByVertical.get(r.vertical) || 0) + r.net_revenue);
  }

  const anomalies: Array<{ vertical: string; current: number; prior: number; change_pct: number }> = [];

  for (const [vertical, current] of currentByVertical) {
    const prior = priorByVertical.get(vertical) || 0;
    if (prior === 0) continue;
    const changePct = ((current - prior) / prior) * 100;
    if (Math.abs(changePct) > ANOMALY_THRESHOLD_PCT) {
      anomalies.push({ vertical, current, prior, change_pct: changePct });
    }
  }

  if (anomalies.length > 0) {
    const drops = anomalies.filter((a) => a.change_pct < 0);
    const spikes = anomalies.filter((a) => a.change_pct > 0);

    if (drops.length > 0) {
      findings.push({
        level: 'warning',
        source: 'mallow-patrol',
        message: `Revenue drops detected in ${drops.length} vertical(s) vs prior week`,
        detail: drops,
        action: 'Investigate root cause: channel changes, lead quality, or market shift',
      });
    }

    if (spikes.length > 0) {
      findings.push({
        level: 'info',
        source: 'mallow-patrol',
        message: `Revenue spikes in ${spikes.length} vertical(s) vs prior week`,
        detail: spikes,
        action: 'Identify winning strategies to replicate across verticals',
      });
    }
  }

  return findings;
}

/**
 * Generate vertical-level trend summaries.
 */
export function generateVerticalSummaries(
  currentWeek: RevenueRow[],
  priorWeek: RevenueRow[],
  targets: Record<string, number>
): VerticalSummary[] {
  const currentByVertical = new Map<string, number>();
  const priorByVertical = new Map<string, number>();

  for (const r of currentWeek) {
    currentByVertical.set(r.vertical, (currentByVertical.get(r.vertical) || 0) + r.net_revenue);
  }
  for (const r of priorWeek) {
    priorByVertical.set(r.vertical, (priorByVertical.get(r.vertical) || 0) + r.net_revenue);
  }

  const summaries: VerticalSummary[] = [];
  for (const [vertical, current] of currentByVertical) {
    const prior = priorByVertical.get(vertical) || 0;
    const target = targets[vertical] || WEEKLY_REVENUE_TARGET;
    const wowChange = prior > 0 ? ((current - prior) / prior) * 100 : 0;

    summaries.push({
      vertical,
      current_revenue: current,
      target,
      pct_of_target: (current / target) * 100,
      trend: wowChange > 5 ? 'up' : wowChange < -5 ? 'down' : 'flat',
      wow_change_pct: wowChange,
    });
  }

  return summaries;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'mallow-revenue-aggregation',
  agent: 'mallow',
  interval_hours: 24,
  run_at: '06:00',
  description: 'Daily revenue aggregation across all verticals with trend analysis and forecasting',
  dispatch_to: 'seldon',
  verticals: ['trading', 'ecommerce', 'lead_gen', 'funding', 'cre'],
};
