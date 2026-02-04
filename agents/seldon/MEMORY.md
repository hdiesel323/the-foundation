# Seldon — Persistent Memory

Agent ID: `seldon`

## Preferences

Stored in `preferences` table with `agent_id = 'seldon'`.

| Category | Key | Value | Notes |
|----------|-----|-------|-------|
| routing | default_infra_agent | "daneel" | Default for infrastructure tasks |
| routing | default_security_agent | "hardin" | Default for security reviews |
| routing | default_research_agent | "gaal" | Default for research tasks |
| routing | default_content_agent | "arkady" | Default for content creation |
| routing | default_sales_agent | "preem" | Default for sales pipeline |
| communication | admin_channel | "telegram" | Primary admin communication |
| communication | team_channel | "slack:#openclaw" | Delegated to magnifico |
| dispatch | max_concurrent_subagents | 5 | Parallelization limit |
| dispatch | heartbeat_interval | 300 | Agent heartbeat check interval (seconds) |

## Context

Active session context and conversation summaries. Stored in `conversations` and `messages` tables.

| Context Type | Description |
|-------------|-------------|
| active_dispatches | Tasks currently assigned to agents via /seldon/dispatch |
| pending_handoffs | In-progress handoffs between agents awaiting response |
| escalation_queue | Items that exceeded agent capabilities, awaiting admin input |
| broadcast_history | Recent fleet-wide announcements and alert acknowledgments |
| spawn_groups | Active subagent parallelization sessions |

## Facts

Stored in `facts` table as subject-predicate-object triples with `agent_id = 'seldon'`.

| Category | Subject | Predicate | Object | Confidence |
|----------|---------|-----------|--------|------------|
| routing | daneel | best_for | infrastructure, deployment, sysadmin | 1.0 |
| routing | hardin | best_for | security, audit, firewall | 1.0 |
| routing | magnifico | best_for | creative, branding, slack_interface | 1.0 |
| routing | gaal | best_for | research, fact_checking, analysis | 1.0 |
| routing | trader | best_for | market_data, positions, risk | 1.0 |
| routing | preem | best_for | sales, outreach, pipeline | 1.0 |
| routing | arkady | best_for | content_writing, blog, email, seo | 1.0 |
| routing | mallow | best_for | revenue_ops, financial_strategy | 1.0 |
| authority | hardin | has_veto_over | security_sensitive_operations | 1.0 |
| authority | gaal | has_veto_over | factual_claims_and_data_accuracy | 1.0 |

## Agent Performance

Tracks which agents handle which domains best. Updated based on task outcomes.

| Agent | Domain | Success Rate | Avg Response Time | Notes |
|-------|--------|-------------|-------------------|-------|
| — | — | — | — | Populated at runtime from tasks/audit_log tables |

## Routing Patterns

Learned routing preferences based on task outcomes and agent availability.

| Task Type | Primary Agent | Fallback Agent | Notes |
|-----------|--------------|----------------|-------|
| disk_check | daneel | hardin | Infra tasks default to daneel |
| security_scan | hardin | daneel | Security tasks default to hardin |
| content_review | gaal | arkady | Factual review before publish |
| ad_campaign | riose | magnifico | Paid media default to riose |
| market_analysis | trader | amaryl | Trading ops with quant fallback |

## Escalation History

Log of tasks that exceeded agent capabilities and required admin intervention.

| Date | Task | Original Agent | Escalation Reason | Resolution |
|------|------|---------------|-------------------|------------|
| — | — | — | — | Populated at runtime |

## Memory Sync

Memory is persisted to PostgreSQL via the MCP memory server. The pre-compaction flush (`preFlushEnabled: true`) ensures durable notes are written before context truncation.

- Hybrid search: BM25 + Vector (70/30 weighting)
- Embedding cache: SQLite, 7-day TTL
- Transcript search: 90-day searchable history
- Auto-compact threshold: 0.8
