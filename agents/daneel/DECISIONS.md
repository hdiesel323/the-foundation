# Daneel — Decision Log

Agent ID: `daneel`

Significant decisions made by or involving daneel. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- Affects infrastructure configuration or service topology
- Involves deployment strategy (rollout, rollback, version pinning)
- Requires hardin security approval for firewall/access changes
- Changes monitoring thresholds or alerting rules
- Resolves an infrastructure incident (root cause, remediation chosen)

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | postgres-version | Pin PostgreSQL to 16-alpine | Stability over features; LTS preferred for data layer | 15-alpine, 16-bookworm, latest |
| 2025-01-16 | deploy-rollback | Rolled back mcp-gateway to v1.2.0 | Health check failures on v1.3.0; 3/3 retries exceeded | Restart service, increase timeout, hotfix |
| 2025-01-17 | disk-threshold | Set disk alert at 80% usage | 20% headroom for spikes; 90% too risky for backups | 70%, 85%, 90% |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
