# Arkady — Persistent Memory

Agent ID: `arkady`

## Preferences

Stored in `preferences` table with `agent_id = 'arkady'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| writing | default_tone | "professional, clear, engaging" | Default writing voice |
| writing | formatting | "structured drafts with headlines, subheads, CTAs" | Standard content format |
| seo | keyword_density | "1-2% target keyword" | SEO best practice baseline |
| content | review_workflow | "draft -> gaal fact-check -> magnifico approval -> publish" | Publication pipeline |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_drafts | Content pieces currently in progress |
| content_pipeline | Pipeline status (drafted/in-review/approved/published) |
| pending_reviews | Content submitted to gaal for factual review |
| creative_briefs | Active briefs received from magnifico |

## Published Content Log

Tracks content arkady has produced and its review status. Stored in `facts` table.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| content | blog_posts | reviewed_by | gaal | 1.0 |
| content | landing_pages | reviewed_by | gaal | 1.0 |
| content | email_sequences | approved_by | magnifico | 1.0 |
| workflow | all_published_content | requires | gaal_factual_review | 1.0 |

## Citation Index

Sources and references used in content production. Linked to specific content pieces for traceability.

| Content ID | Source | URL/Reference | Verified By | Date |
|-----------|--------|---------------|-------------|------|
| — | — | — | — | — |

## Review Outcomes Log

Tracks factual review results from gaal on arkady's content submissions.

| Date | Content Piece | Reviewer | Outcome | Notes |
|------|--------------|----------|---------|-------|
| — | — | — | — | — |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
