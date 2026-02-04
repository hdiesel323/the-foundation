/**
 * Trader Patrol — 30-minute position monitoring.
 *
 * Monitors: stop-loss enforcement, unrealized PnL alerts,
 * position sizing compliance, and daily loss limits.
 * Triggers P0 alert if stop-loss is breached.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const STOP_LOSS_DEFAULT_PCT = 5;
const TAKE_PROFIT_DEFAULT_PCT = 15;
const MAX_POSITION_PCT = 10;
const MAX_DAILY_LOSS_PCT = 3;
const STOP_LOSS_APPROACHING_PCT = 1;

interface Position {
  symbol: string;
  qty: number;
  avg_entry_price: number;
  current_price: number;
  unrealized_pnl: number;
  unrealized_pnl_pct: number;
  market_value: number;
  stop_loss?: number;
  take_profit?: number;
}

interface PortfolioSummary {
  equity: number;
  buying_power: number;
  cash: number;
  daily_pnl: number;
  daily_pnl_pct: number;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Check stop-loss enforcement — trigger P0 alert if price breaches stop.
 */
export function checkStopLosses(positions: Position[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const breached = positions.filter((p) => {
    const stop = p.stop_loss || p.avg_entry_price * (1 - STOP_LOSS_DEFAULT_PCT / 100);
    return p.current_price <= stop;
  });

  if (breached.length > 0) {
    findings.push({
      level: 'critical',
      source: 'trader-patrol',
      message: `P0 ALERT: ${breached.length} position(s) breached stop-loss — IMMEDIATE ACTION REQUIRED`,
      detail: breached.map((p) => ({
        symbol: p.symbol,
        entry: p.avg_entry_price,
        current: p.current_price,
        stop_loss: p.stop_loss || p.avg_entry_price * (1 - STOP_LOSS_DEFAULT_PCT / 100),
        unrealized_pnl: p.unrealized_pnl,
        action: 'SELL IMMEDIATELY',
      })),
      action: 'Execute market sell orders for all breached positions',
    });
  }

  // Approaching stop-loss warning
  const approaching = positions.filter((p) => {
    const stop = p.stop_loss || p.avg_entry_price * (1 - STOP_LOSS_DEFAULT_PCT / 100);
    const warningPrice = stop * (1 + STOP_LOSS_APPROACHING_PCT / 100);
    return p.current_price > stop && p.current_price <= warningPrice;
  });

  if (approaching.length > 0) {
    findings.push({
      level: 'warning',
      source: 'trader-patrol',
      message: `${approaching.length} position(s) approaching stop-loss (within ${STOP_LOSS_APPROACHING_PCT}%)`,
      detail: approaching.map((p) => ({
        symbol: p.symbol,
        current: p.current_price,
        stop_loss: p.stop_loss || p.avg_entry_price * (1 - STOP_LOSS_DEFAULT_PCT / 100),
        distance_pct: (((p.current_price - (p.stop_loss || p.avg_entry_price * (1 - STOP_LOSS_DEFAULT_PCT / 100))) / p.current_price) * 100).toFixed(2),
      })),
      action: 'Review positions and confirm stop-loss orders are in place',
    });
  }

  return findings;
}

/**
 * Check unrealized PnL and alert on significant moves.
 */
export function checkUnrealizedPnL(positions: Position[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const bigLosers = positions.filter((p) => p.unrealized_pnl_pct < -3);
  const bigWinners = positions.filter((p) => p.unrealized_pnl_pct > TAKE_PROFIT_DEFAULT_PCT);

  if (bigLosers.length > 0) {
    findings.push({
      level: 'warning',
      source: 'trader-patrol',
      message: `${bigLosers.length} position(s) with >3% unrealized loss`,
      detail: bigLosers.map((p) => ({
        symbol: p.symbol,
        pnl: p.unrealized_pnl,
        pnl_pct: p.unrealized_pnl_pct.toFixed(2),
        market_value: p.market_value,
      })),
      action: 'Evaluate thesis — hold, reduce, or exit',
    });
  }

  if (bigWinners.length > 0) {
    findings.push({
      level: 'info',
      source: 'trader-patrol',
      message: `${bigWinners.length} position(s) exceeding take-profit target (${TAKE_PROFIT_DEFAULT_PCT}%)`,
      detail: bigWinners.map((p) => ({
        symbol: p.symbol,
        pnl: p.unrealized_pnl,
        pnl_pct: p.unrealized_pnl_pct.toFixed(2),
        action: 'Consider partial exit or trailing stop',
      })),
      action: 'Review for profit-taking or trailing stop adjustment',
    });
  }

  return findings;
}

/**
 * Check position sizing compliance.
 */
export function checkPositionSizing(positions: Position[], portfolio: PortfolioSummary): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  const oversized = positions.filter(
    (p) => (p.market_value / portfolio.equity) * 100 > MAX_POSITION_PCT
  );

  if (oversized.length > 0) {
    findings.push({
      level: 'warning',
      source: 'trader-patrol',
      message: `${oversized.length} position(s) exceeding ${MAX_POSITION_PCT}% portfolio allocation limit`,
      detail: oversized.map((p) => ({
        symbol: p.symbol,
        market_value: p.market_value,
        pct_of_portfolio: ((p.market_value / portfolio.equity) * 100).toFixed(1),
        excess: p.market_value - portfolio.equity * (MAX_POSITION_PCT / 100),
      })),
      action: 'Trim oversized positions to comply with risk limits',
    });
  }

  return findings;
}

/**
 * Check daily loss limit.
 */
export function checkDailyLossLimit(portfolio: PortfolioSummary): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  if (portfolio.daily_pnl_pct < -MAX_DAILY_LOSS_PCT) {
    findings.push({
      level: 'critical',
      source: 'trader-patrol',
      message: `P0 ALERT: Daily loss limit breached (${portfolio.daily_pnl_pct.toFixed(2)}% vs -${MAX_DAILY_LOSS_PCT}% limit)`,
      detail: {
        daily_pnl: portfolio.daily_pnl,
        daily_pnl_pct: portfolio.daily_pnl_pct,
        equity: portfolio.equity,
      },
      action: 'HALT TRADING — close all positions and review risk framework',
    });
  } else if (portfolio.daily_pnl_pct < -(MAX_DAILY_LOSS_PCT * 0.7)) {
    findings.push({
      level: 'warning',
      source: 'trader-patrol',
      message: `Daily loss approaching limit (${portfolio.daily_pnl_pct.toFixed(2)}%)`,
      detail: {
        daily_pnl: portfolio.daily_pnl,
        remaining_before_halt: (MAX_DAILY_LOSS_PCT + portfolio.daily_pnl_pct).toFixed(2),
      },
      action: 'Reduce exposure — avoid new positions until recovery',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'trader-position-monitor',
  agent: 'trader',
  interval_minutes: 30,
  description: 'Position monitoring with stop-loss enforcement, PnL alerts, and risk compliance',
  dispatch_to: 'seldon',
  priority: 'P0',
};
