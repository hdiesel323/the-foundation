/**
 * Amaryl Patrol — 4-hourly prediction market scan.
 *
 * Scans prediction market platforms for arbitrage opportunities,
 * statistical edge detection, and cross-platform price discrepancies.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const MIN_EDGE_PCT = 10;
const MIN_ARBITRAGE_SPREAD_PCT = 3;
const PLATFORMS = ['polymarket', 'kalshi', 'metaculus'];

interface MarketOpportunity {
  platform: string;
  market_id: string;
  question: string;
  yes_price: number;
  no_price: number;
  volume_24h: number;
  liquidity: number;
  closes_at: string;
}

interface ArbitrageOpportunity {
  question: string;
  platform_a: string;
  platform_b: string;
  price_a: number;
  price_b: number;
  spread_pct: number;
  estimated_profit: number;
}

interface EdgeOpportunity {
  platform: string;
  market_id: string;
  question: string;
  market_price: number;
  model_estimate: number;
  edge_pct: number;
  confidence: number;
  category: string;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Detect cross-platform arbitrage — same question priced differently.
 */
export function detectArbitrage(markets: MarketOpportunity[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  // Group markets by normalized question text
  const byQuestion = new Map<string, MarketOpportunity[]>();
  for (const m of markets) {
    const key = m.question.toLowerCase().trim();
    const existing = byQuestion.get(key) || [];
    existing.push(m);
    byQuestion.set(key, existing);
  }

  const arbs: ArbitrageOpportunity[] = [];
  for (const [question, entries] of byQuestion) {
    if (entries.length < 2) continue;
    for (let i = 0; i < entries.length; i++) {
      for (let j = i + 1; j < entries.length; j++) {
        const a = entries[i];
        const b = entries[j];
        // Arb: buy YES on cheaper, sell YES on more expensive
        const spread = Math.abs(a.yes_price - b.yes_price);
        const spreadPct = (spread / Math.min(a.yes_price, b.yes_price)) * 100;
        if (spreadPct >= MIN_ARBITRAGE_SPREAD_PCT) {
          arbs.push({
            question,
            platform_a: a.platform,
            platform_b: b.platform,
            price_a: a.yes_price,
            price_b: b.yes_price,
            spread_pct: spreadPct,
            estimated_profit: spread * Math.min(a.liquidity, b.liquidity),
          });
        }
      }
    }
  }

  if (arbs.length > 0) {
    arbs.sort((a, b) => b.estimated_profit - a.estimated_profit);
    findings.push({
      level: 'warning',
      source: 'amaryl-patrol',
      message: `${arbs.length} cross-platform arbitrage opportunities detected`,
      detail: arbs.slice(0, 10),
      action: 'Review and execute arbitrage trades if within risk parameters',
    });
  }

  return findings;
}

/**
 * Identify statistical edge — markets where our model estimate diverges from market price.
 */
export function detectStatisticalEdge(edges: EdgeOpportunity[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const highEdge = edges.filter((e) => e.edge_pct >= MIN_EDGE_PCT && e.confidence >= 0.7);

  if (highEdge.length > 0) {
    highEdge.sort((a, b) => b.edge_pct * b.confidence - a.edge_pct * a.confidence);
    findings.push({
      level: 'info',
      source: 'amaryl-patrol',
      message: `${highEdge.length} prediction markets with statistical edge >=${MIN_EDGE_PCT}%`,
      detail: highEdge.slice(0, 10).map((e) => ({
        platform: e.platform,
        question: e.question,
        market_price: e.market_price,
        model_estimate: e.model_estimate,
        edge_pct: e.edge_pct.toFixed(1),
        confidence: e.confidence.toFixed(2),
        category: e.category,
      })),
      action: 'Evaluate for position entry within prediction market allocation',
    });
  }

  return findings;
}

/**
 * Check market expiration — positions in markets closing soon.
 */
export function checkExpiringMarkets(markets: MarketOpportunity[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const now = Date.now();
  const expiringSoon = markets.filter((m) => {
    const closes = new Date(m.closes_at).getTime();
    const hoursUntilClose = (closes - now) / (1000 * 60 * 60);
    return hoursUntilClose > 0 && hoursUntilClose <= 24;
  });

  if (expiringSoon.length > 0) {
    findings.push({
      level: 'info',
      source: 'amaryl-patrol',
      message: `${expiringSoon.length} markets closing within 24 hours`,
      detail: expiringSoon.map((m) => ({
        platform: m.platform,
        question: m.question,
        yes_price: m.yes_price,
        closes_at: m.closes_at,
      })),
      action: 'Review positions in expiring markets for exit or hold',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'amaryl-prediction-scan',
  agent: 'amaryl',
  interval_hours: 4,
  description: 'Prediction market scanning: arbitrage detection, edge identification, expiration alerts',
  dispatch_to: 'seldon',
  platforms: PLATFORMS,
};
