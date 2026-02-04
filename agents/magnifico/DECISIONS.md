# Magnifico — Decision Log

Agent ID: `magnifico`

Significant decisions made by or involving magnifico. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- Affects brand voice, messaging, or creative direction
- Involves delegation to another agent
- Changes campaign strategy or priorities
- Resolves a conflict between creative options

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | brand-tone | Use conversational tone for all Slack comms | Matches user preference for warmth; formal felt stiff | Formal, semi-formal, casual |
| 2025-01-16 | campaign-channel | Route paid media briefs to riose via Seldon | riose owns ad spend optimization | Direct Slack DM, email brief |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
