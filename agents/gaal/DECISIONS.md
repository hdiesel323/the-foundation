# Gaal — Decision Log

Agent ID: `gaal`

Significant decisions made by or involving gaal. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- VETO or APPROVE of published content based on factual accuracy
- Selects research methodology or source prioritization
- Resolves conflicting data between sources
- Assigns confidence ratings to contested claims
- Changes fact-checking criteria or review thresholds

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | arkady-blog-veto | VETO arkady blog post on market trends | 3 unsupported statistical claims; no primary sources cited | Approve with disclaimers, request revisions only |
| 2025-01-16 | source-priority | Prioritize peer-reviewed over news articles for health claims | News articles often misrepresent study findings | Equal weighting, news-first for recency |
| 2025-01-17 | confidence-threshold | Set MEDIUM confidence floor for publication | LOW confidence claims too risky for brand reputation | Allow LOW with disclaimers, HIGH only |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
