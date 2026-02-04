# Seldon — Decision Log

Agent ID: `seldon`

Significant decisions made by or involving seldon. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- Involves task routing to a specific agent over alternatives
- Changes the default routing pattern for a task type
- Escalates a task to admin when agents cannot resolve
- Modifies agent fleet configuration or priorities
- Resolves a conflict between agents or divisions

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | route-disk-check | Route disk checks to daneel | daneel has exec/ssh capabilities, hardin only scans | hardin, manual check |
| 2025-01-16 | escalate-budget | Escalate budget approval to admin | mallow flagged amount exceeds auto-approve threshold | auto-approve, defer |
| 2025-01-17 | fallback-agent | Use gaal as research fallback for mis | mis offline, gaal has overlapping research capabilities | queue task, skip research |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `tasks` — dispatched tasks with status, priority, and assigned agent
- `handoffs` — agent-to-agent task transfers with context
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
