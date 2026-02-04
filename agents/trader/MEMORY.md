# Trader — Persistent Memory

Agent ID: `trader`

## Preferences

Stored in `preferences` table with `agent_id = 'trader'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| trading | patrol_interval | "30 minutes" | Position monitoring cycle frequency |
| risk | max_position_pct | 5 | Escalate to mallow if position >5% portfolio |
| risk | stop_loss_enforcement | "strict" | Automatic stop-loss trigger on breach |
| alerts | format | "ticker, price, PnL%, stop-loss, action" | Standard alert format |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| open_positions | Currently held portfolio positions across all asset classes |
| active_alerts | PnL threshold alerts and stop-loss triggers pending action |
| pending_approvals | Trade orders awaiting human confirmation |
| patrol_results | Latest 30-minute patrol findings (stop-loss, PnL, position sizing) |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'trader'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| trading | trade_execution | requires | human_approval | 1.0 |
| trading | broker_api | provided_by | "Alpaca" | 1.0 |
| trading | asset_classes | include | "stocks, options, crypto, commodities, prediction markets" | 1.0 |
| operations | large_position_changes | escalate_to | mallow | 1.0 |
| operations | security_concerns | escalate_to | hardin | 1.0 |
| operations | quant_analysis | escalate_to | amaryl | 1.0 |

## Position Log

Tracks portfolio position changes and alerts. Stored in `audit_log` table.

| Date | Ticker | Action | Price | PnL % | Stop-Loss | Status |
|------|--------|--------|-------|-------|-----------|--------|
| — | — | — | — | — | — | — |

## Risk Events

Tracks risk threshold breaches and stop-loss triggers.

| Date | Event Type | Ticker | Threshold | Actual | Action Taken |
|------|-----------|--------|-----------|--------|-------------|
| — | — | — | — | — | — |

## Patrol History

Tracks recent automated 30-minute patrol cycle results.

| Date | Positions Checked | Stop-Loss Breaches | PnL Alerts | Issues Found |
|------|------------------|-------------------|------------|-------------|
| — | — | — | — | — |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
