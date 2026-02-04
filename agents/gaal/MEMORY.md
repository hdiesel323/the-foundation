# Gaal — Persistent Memory

Agent ID: `gaal`

## Preferences

Stored in `preferences` table with `agent_id = 'gaal'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| research | default_confidence | "HIGH/MEDIUM/LOW" | Confidence rating scale for findings |
| research | citation_required | true | All claims must have sources |
| review | veto_threshold | "any unverified factual claim" | Zero-tolerance for unsourced assertions |
| reports | format | "objective, methodology, findings, confidence, sources" | Structured research report template |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_research | Research investigations currently in progress |
| pending_reviews | Content submissions awaiting factual VETO/APPROVE |
| source_library | Accumulated authoritative sources and references |
| review_queue | Content from arkady and other agents pending fact-check |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'gaal'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| authority | published_content | requires | factual_review | 1.0 |
| authority | factual_claims | require | citation | 1.0 |
| operations | infrastructure_requests | escalate_to | daneel | 1.0 |
| operations | security_concerns | escalate_to | hardin | 1.0 |
| operations | user_communications | escalate_to | magnifico | 1.0 |
| operations | intelligence_coordination | escalate_to | demerzel | 1.0 |

## VETO/APPROVE Log

Tracks factual review decisions made by gaal on content submissions.

| Date | Content Piece | From Agent | Decision | Factual Issues | Sources |
|------|--------------|-----------|----------|----------------|---------|
| — | — | — | — | — | — |

## Research Index

Tracks completed research investigations and their findings.

| Date | Topic | Confidence | Key Finding | Sources Count |
|------|-------|-----------|-------------|---------------|
| — | — | — | — | — |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
