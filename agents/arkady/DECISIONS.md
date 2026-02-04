# Arkady — Decision Log

Agent ID: `arkady`

Significant decisions made by or involving arkady. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- Affects content tone, structure, or messaging approach
- Involves choosing between content formats (blog vs. email vs. landing page)
- Responds to gaal's factual review feedback (accept/revise/dispute)
- Changes SEO strategy or keyword targeting
- Resolves conflicting direction from creative briefs

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | blog-tone | Use technical tone for developer audience posts | Target audience prefers specificity over marketing speak | Conversational, persuasive, formal |
| 2025-01-16 | gaal-review-response | Revised claims in landing page per gaal fact-check | gaal flagged unsupported performance statistics | Dispute with sources, remove claims entirely |
| 2025-01-17 | email-sequence-length | 5-email nurture sequence instead of 7 | Analytics show drop-off after email 5; shorter = higher completion | 3-email, 7-email, 10-email |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
