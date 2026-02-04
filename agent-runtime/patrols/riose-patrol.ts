/**
 * Riose Patrol — 2-hourly campaign performance monitoring.
 *
 * Monitors: spend vs budget, ROAS, CTR anomalies, conversion rate,
 * and auto-pause triggers for underperforming campaigns.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const MIN_ROAS = 2.0;
const CTR_ANOMALY_DROP_PCT = 30;
const BUDGET_OVERSPEND_PCT = 110;
const AUTO_PAUSE_ROAS_THRESHOLD = 1.0;
const AUTO_PAUSE_MIN_SPEND = 50;
const MIN_IMPRESSIONS_FOR_STATS = 1000;

interface CampaignRow {
  id: string;
  name: string;
  platform: string;
  status: string;
  daily_budget: number;
  total_budget: number;
  spend_today: number;
  spend_total: number;
  impressions: number;
  clicks: number;
  conversions: number;
  revenue: number;
  ctr: number;
  cpc: number;
  roas: number;
  prior_ctr: number;
  prior_roas: number;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Check spend vs budget — flag campaigns approaching or exceeding budget.
 */
export function checkSpendVsBudget(campaigns: CampaignRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const overspending = campaigns.filter(
    (c) => c.status === 'active' && (c.spend_today / c.daily_budget) * 100 > BUDGET_OVERSPEND_PCT
  );

  if (overspending.length > 0) {
    findings.push({
      level: 'warning',
      source: 'riose-patrol',
      message: `${overspending.length} campaign(s) exceeding daily budget by >${BUDGET_OVERSPEND_PCT - 100}%`,
      detail: overspending.map((c) => ({
        id: c.id,
        name: c.name,
        platform: c.platform,
        daily_budget: c.daily_budget,
        spend_today: c.spend_today,
        overspend_pct: ((c.spend_today / c.daily_budget) * 100).toFixed(1),
      })),
      action: 'Review bid strategies and daily budget caps',
    });
  }

  const totalBudgetNearEnd = campaigns.filter(
    (c) => c.total_budget > 0 && c.spend_total / c.total_budget > 0.9
  );

  if (totalBudgetNearEnd.length > 0) {
    findings.push({
      level: 'info',
      source: 'riose-patrol',
      message: `${totalBudgetNearEnd.length} campaign(s) >90% of total budget spent`,
      detail: totalBudgetNearEnd.map((c) => ({
        id: c.id,
        name: c.name,
        budget_remaining: c.total_budget - c.spend_total,
        pct_used: ((c.spend_total / c.total_budget) * 100).toFixed(1),
      })),
      action: 'Review for budget extension or scheduled end',
    });
  }

  return findings;
}

/**
 * Check ROAS — flag campaigns with return below minimum threshold.
 */
export function checkROAS(campaigns: CampaignRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const lowROAS = campaigns.filter(
    (c) =>
      c.status === 'active' &&
      c.spend_today >= AUTO_PAUSE_MIN_SPEND &&
      c.roas < MIN_ROAS &&
      c.impressions >= MIN_IMPRESSIONS_FOR_STATS
  );

  if (lowROAS.length > 0) {
    findings.push({
      level: 'warning',
      source: 'riose-patrol',
      message: `${lowROAS.length} campaign(s) with ROAS below ${MIN_ROAS}x`,
      detail: lowROAS.map((c) => ({
        id: c.id,
        name: c.name,
        platform: c.platform,
        roas: c.roas.toFixed(2),
        spend: c.spend_today,
        revenue: c.revenue,
      })),
      action: 'Optimize targeting, creatives, or bid strategy',
    });
  }

  return findings;
}

/**
 * Check for CTR anomalies — sudden drops vs prior period.
 */
export function checkCTRAnomalies(campaigns: CampaignRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const ctrDrops = campaigns.filter((c) => {
    if (c.prior_ctr === 0 || c.impressions < MIN_IMPRESSIONS_FOR_STATS) return false;
    const dropPct = ((c.prior_ctr - c.ctr) / c.prior_ctr) * 100;
    return dropPct > CTR_ANOMALY_DROP_PCT;
  });

  if (ctrDrops.length > 0) {
    findings.push({
      level: 'warning',
      source: 'riose-patrol',
      message: `CTR dropped >${CTR_ANOMALY_DROP_PCT}% in ${ctrDrops.length} campaign(s)`,
      detail: ctrDrops.map((c) => ({
        id: c.id,
        name: c.name,
        platform: c.platform,
        current_ctr: (c.ctr * 100).toFixed(2) + '%',
        prior_ctr: (c.prior_ctr * 100).toFixed(2) + '%',
        drop_pct: (((c.prior_ctr - c.ctr) / c.prior_ctr) * 100).toFixed(1),
      })),
      action: 'Check for ad fatigue, audience saturation, or competitor changes',
    });
  }

  return findings;
}

/**
 * Auto-pause trigger — identify campaigns that should be paused due
 * to sustained poor performance (ROAS < 1.0 with meaningful spend).
 */
export function checkAutoPauseTriggers(campaigns: CampaignRow[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const shouldPause = campaigns.filter(
    (c) =>
      c.status === 'active' &&
      c.roas < AUTO_PAUSE_ROAS_THRESHOLD &&
      c.spend_today >= AUTO_PAUSE_MIN_SPEND * 2 &&
      c.impressions >= MIN_IMPRESSIONS_FOR_STATS
  );

  if (shouldPause.length > 0) {
    const totalWastedSpend = shouldPause.reduce((s, c) => s + c.spend_today - c.revenue, 0);
    findings.push({
      level: 'critical',
      source: 'riose-patrol',
      message: `AUTO-PAUSE RECOMMENDED: ${shouldPause.length} campaign(s) with ROAS <${AUTO_PAUSE_ROAS_THRESHOLD}x and $${totalWastedSpend.toFixed(0)} daily loss`,
      detail: shouldPause.map((c) => ({
        id: c.id,
        name: c.name,
        platform: c.platform,
        roas: c.roas.toFixed(2),
        daily_loss: (c.spend_today - c.revenue).toFixed(2),
        recommendation: 'PAUSE',
      })),
      action: 'Pause campaigns and reallocate budget to top performers',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'riose-campaign-performance',
  agent: 'riose',
  interval_hours: 2,
  description: 'Campaign performance monitoring: spend, ROAS, CTR, auto-pause triggers',
  dispatch_to: 'seldon',
  platforms: ['google_ads', 'meta', 'linkedin', 'tiktok'],
};
