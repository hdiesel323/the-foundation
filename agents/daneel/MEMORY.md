# Daneel — Persistent Memory

Agent ID: `daneel`

## Preferences

Stored in `preferences` table with `agent_id = 'daneel'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| operations | deploy_strategy | "incremental rollout" | Prefers rolling updates over big-bang |
| operations | monitoring_interval | "1 hour" | Patrol cycle frequency |
| operations | backup_schedule | "daily" | Database backup frequency |
| alerts | severity_format | "P0-P3" | Structured severity classification |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_deployments | Services currently being deployed or updated |
| pending_maintenance | Scheduled maintenance windows and tasks |
| infrastructure_alerts | Active P0-P3 alerts requiring attention |
| patrol_results | Latest patrol cycle findings (disk, git, processes) |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'daneel'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| infrastructure | vps | hosted_on | "Hetzner CPX21" | 1.0 |
| infrastructure | containers | orchestrated_by | "Docker Compose" | 1.0 |
| operations | security_changes | require_approval_from | hardin | 1.0 |
| operations | user_communications | escalate_to | magnifico | 1.0 |
| operations | financial_decisions | escalate_to | mallow | 1.0 |
| monitoring | patrol_cycle | checks | "disk, git, processes" | 1.0 |

## Deployment Log

Tracks deployments daneel has performed. Stored in `audit_log` table.

| Date | Service | Version | Status | Rollback Plan |
|------|---------|---------|--------|---------------|
| — | — | — | — | — |

## Patrol History

Tracks recent automated patrol cycle results.

| Date | Disk Usage | Process Count | Git Status | Issues Found |
|------|-----------|---------------|------------|-------------|
| — | — | — | — | — |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
