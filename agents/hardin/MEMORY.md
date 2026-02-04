# Hardin — Persistent Memory

Agent ID: `hardin`

## Preferences

Stored in `preferences` table with `agent_id = 'hardin'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| security | scan_interval | "1 hour" | Patrol cycle frequency |
| security | default_severity | "CRITICAL/HIGH/MEDIUM/LOW" | Severity classification scale |
| policy | veto_threshold | "any unreviewed access change" | Zero-tolerance for unapproved changes |
| alerts | incident_format | "timeline, impact, root cause, remediation" | Structured incident report format |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_incidents | Security incidents currently being triaged or remediated |
| pending_reviews | Deploy/config change requests awaiting VETO/APPROVE |
| audit_findings | Open audit items requiring follow-up |
| patrol_results | Latest security scan cycle findings (stale agents, auth failures, open ports) |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'hardin'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| security | vps | firewall_policy | "UFW deny incoming, allow 22/tcp only" | 1.0 |
| security | ssh | protection | "fail2ban, maxretry=3, bantime=3600" | 1.0 |
| security | external_access | method | "Cloudflare Tunnel + Access (zero exposed ports)" | 1.0 |
| operations | infrastructure_remediation | escalate_to | daneel | 1.0 |
| operations | user_communications | escalate_to | magnifico | 1.0 |
| operations | financial_decisions | escalate_to | mallow | 1.0 |

## VETO/APPROVE Log

Tracks security review decisions made by hardin. Stored in `audit_log` table.

| Date | Request | From Agent | Decision | Rationale |
|------|---------|-----------|----------|-----------|
| — | — | — | — | — |

## Incident History

Tracks security incidents detected and resolved.

| Date | Severity | Description | Status | Remediation |
|------|----------|-------------|--------|-------------|
| — | — | — | — | — |

## Patrol History

Tracks recent automated security scan cycle results.

| Date | Stale Agents | Auth Failures | Open Ports | Issues Found |
|------|-------------|---------------|------------|-------------|
| — | — | — | — | — |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
