# Magnifico — Persistent Memory

Agent ID: `magnifico`

## Preferences

Stored in `preferences` table with `agent_id = 'magnifico'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| brand | voice_tone | "warm, direct, articulate" | Default brand voice |
| brand | formatting | "bullet points, structured briefs" | Preferred output format |
| channels | primary | "slack:#openclaw" | Default communication channel |
| channels | fallback | "telegram" | Fallback via seldon routing |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_conversations | Open threads in Slack #openclaw |
| campaign_briefs | In-progress creative briefs and campaign plans |
| pending_delegations | Tasks dispatched to other agents via Seldon |
| escalation_queue | Items waiting on daneel/hardin/mallow/gaal response |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'magnifico'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| brand | company | has_voice | "warm, direct, articulate" | 1.0 |
| brand | status_reports | use_format | "concise bullet points" | 1.0 |
| delegation | infrastructure_tasks | escalate_to | daneel | 1.0 |
| delegation | security_concerns | escalate_to | hardin | 1.0 |
| delegation | revenue_operations | escalate_to | mallow | 1.0 |
| delegation | factual_verification | escalate_to | gaal | 1.0 |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
