# Trading Journal Entry

## Trade ID: {{trade_id}}
**Date:** {{date}}
**Symbol:** {{symbol}}
**Direction:** {{long_short}}

## Thesis
**Setup type:** {{setup_type}}
**Conviction level:** {{1-5}}/5
**Thesis:**
> {{thesis_description}}

**Key catalysts:**
- {{catalyst_1}}
- {{catalyst_2}}

## Entry
| Field | Value |
|-------|-------|
| Entry price | {{entry_price}} |
| Entry time | {{entry_time}} |
| Position size | {{qty}} shares ({{pct_portfolio}}% of portfolio) |
| Entry value | {{entry_value}} |

## Risk/Reward
| Field | Value |
|-------|-------|
| Stop loss | {{stop_loss}} ({{stop_loss_pct}}%) |
| Take profit | {{take_profit}} ({{take_profit_pct}}%) |
| Risk/Reward ratio | {{risk_reward}} |
| Max risk ($) | {{max_risk}} |

## Exit
| Field | Value |
|-------|-------|
| Exit price | {{exit_price}} |
| Exit time | {{exit_time}} |
| Exit reason | {{exit_reason}} |
| Holding period | {{holding_period}} |

## Outcome
| Field | Value |
|-------|-------|
| P&L ($) | {{pnl_dollars}} |
| P&L (%) | {{pnl_pct}} |
| Result | {{win_loss_breakeven}} |

## Analysis

### What went right
- {{right_1}}

### What went wrong
- {{wrong_1}}

### Market conditions
- Trend: {{uptrend_downtrend_sideways}}
- Volatility: {{low_normal_high}}
- Volume: {{below_normal_above}}

## Learning
**Category:** {{technical | fundamental | risk_management | psychology | execution}}
**Priority:** {{P0-P3}}
**Key takeaway:**
> {{learning_summary}}

**Suggested action:**
> {{action_to_improve}}

## Self-Improvement Loop
- [ ] Log to LEARNINGS.md if pattern detected (3+ similar outcomes)
- [ ] Update trading rules if stop-loss/take-profit was suboptimal
- [ ] Adjust position sizing model if risk was miscalculated
- [ ] Review thesis quality — was the setup valid?
- [ ] Check if this trade type should be added/removed from playbook
