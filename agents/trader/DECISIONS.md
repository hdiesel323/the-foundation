# Trader — Decision Log

Agent ID: `trader`

Significant decisions made by or involving trader. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- Sets or adjusts stop-loss levels for positions
- Changes risk thresholds or position sizing rules
- Escalates a large position change to mallow for approval
- Responds to a risk event (stop-loss breach, drawdown, unusual volume)
- Modifies patrol cycle parameters or alert thresholds

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | stop-loss-btc | Set BTC stop-loss at -8% from entry | Crypto volatility requires wider bands; -5% triggered false stops | -5%, -10%, trailing 7% |
| 2025-01-16 | position-escalation | Escalated AAPL position increase to mallow | Would exceed 5% portfolio threshold; requires VP approval | Auto-approve within limits, skip and hold |
| 2025-01-17 | patrol-frequency | Keep 30-minute patrol cycle | Market hours volatility needs frequent checks; 1-hour too slow | 15-minute, 1-hour, market-hours only |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
