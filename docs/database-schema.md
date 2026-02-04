# Database Schema

The Foundation uses PostgreSQL 16 for all persistent state. The schema is split across three migration files in `init-scripts/`.

## Migrations

Run in order:

```bash
cat init-scripts/01-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/02-business-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/03-discord-threads.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
```

## Extensions

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- Encryption
-- CREATE EXTENSION IF NOT EXISTS "vector";   -- Phase 2: semantic search
```

---

## Core Tables (01-schema.sql)

### agents

Multi-agent registry. Each agent registers here on startup.

| Column | Type | Description |
|--------|------|-------------|
| id | VARCHAR(100) PK | Agent identifier (e.g., "seldon") |
| name | VARCHAR(255) | Display name |
| role | VARCHAR(100) | Agent role |
| location | VARCHAR(100) | Where it runs |
| endpoint | VARCHAR(500) | Callback URL |
| status | VARCHAR(50) | "online", "offline", "healthy" |
| capabilities | TEXT[] | Capability list |
| last_heartbeat | TIMESTAMPTZ | Last heartbeat time |
| registered_at | TIMESTAMPTZ | Registration time |
| metadata | JSONB | Additional data |

### tasks

Central task tracking table. Every task, subtask, and pre-flight request is stored here.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Task ID |
| agent_id | VARCHAR(100) | Assigned agent |
| lead_agent | VARCHAR(100) | Lead agent for the task |
| conversation_id | UUID FK | Linked conversation |
| name | VARCHAR(500) | Task name |
| description | TEXT | Task description |
| status | VARCHAR(50) | pending, awaiting_approval, in_progress, completed, cancelled |
| priority | INTEGER | 1 (critical) to 8 (low) |
| scheduled_at | TIMESTAMPTZ | Scheduled execution time |
| started_at | TIMESTAMPTZ | When work began |
| completed_at | TIMESTAMPTZ | When completed |
| result | JSONB | Task result |
| error_message | TEXT | Error details |
| retry_count | INTEGER | Current retry count |
| max_retries | INTEGER | Max retries (default 3) |
| acceptance_criteria | JSONB | Result validation criteria |
| discord_thread_id | VARCHAR(100) | Linked Discord thread |
| discord_channel_id | VARCHAR(100) | Discord channel |
| discord_message_url | TEXT | Thread URL |
| participating_agents | TEXT[] | All agents that worked on this |
| completion_summary | TEXT | Final summary |
| archived_at | TIMESTAMPTZ | When archived |
| metadata | JSONB | Workflow links, preflight data, etc. |

### workflows

Workflow execution tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Workflow ID |
| name | VARCHAR(500) | Workflow name |
| description | TEXT | Description |
| steps | JSONB | Step definitions |
| status | VARCHAR(20) | pending, in_progress, completed, failed |
| current_step | INTEGER | Current step index |
| result | JSONB | Final result |
| error_message | TEXT | Error details |
| created_by | VARCHAR(100) FK | Creating agent |
| metadata | JSONB | step_status, step_task_ids, step_results |

### handoffs

Agent-to-agent task transfers.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Handoff ID |
| from_agent | VARCHAR(100) FK | Source agent |
| to_agent | VARCHAR(100) FK | Target agent |
| context | JSONB | Handoff context |
| status | VARCHAR(50) | pending, awaiting_response, completed |
| result | JSONB | Handoff result |

### conversations

Session tracking for agent conversations.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Conversation ID |
| agent_id | VARCHAR(100) | Agent |
| title | VARCHAR(500) | Conversation title |
| context_summary | TEXT | Summary |
| status | VARCHAR(50) | active, archived |

### messages

Individual messages within conversations.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Message ID |
| conversation_id | UUID FK | Parent conversation |
| agent_id | VARCHAR(100) | Agent |
| role | VARCHAR(50) | user, assistant, system |
| content | TEXT | Message content |
| tool_calls | JSONB | Tool call data |
| tokens_used | INTEGER | Token count |

### facts

Knowledge triples (subject-predicate-object) with temporal validity.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Fact ID |
| agent_id | VARCHAR(100) | Owning agent (or "shared") |
| category | VARCHAR(100) | Fact category |
| subject | VARCHAR(500) | Subject |
| predicate | VARCHAR(255) | Relationship |
| object | TEXT | Object |
| confidence | DECIMAL(3,2) | Confidence score (0-1) |
| source | VARCHAR(255) | Source |
| valid_from | TIMESTAMPTZ | Valid start |
| valid_until | TIMESTAMPTZ | Expiry |

### entities

Knowledge graph entities (contacts, projects, companies).

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Entity ID |
| type | VARCHAR(100) | Entity type |
| name | VARCHAR(500) | Entity name |
| aliases | TEXT[] | Alternative names |
| attributes | JSONB | Entity attributes |

### relationships

Relationships between entities.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Relationship ID |
| from_entity_id | UUID FK | Source entity |
| to_entity_id | UUID FK | Target entity |
| relationship_type | VARCHAR(100) | Relationship type |
| attributes | JSONB | Relationship attributes |

### insights

Shared agent memory with TTL. Agents post insights that expire after a configurable duration.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Insight ID |
| agent_id | VARCHAR(100) FK | Source agent |
| category | VARCHAR(100) | Category |
| content | TEXT | Insight content |
| confidence | DECIMAL(3,2) | Confidence (default 0.80) |
| ttl_seconds | INTEGER | Time-to-live (default 3600) |
| expires_at | TIMESTAMPTZ | Expiry time |

### activities

Event feed tracking all system events.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Activity ID |
| event_type | VARCHAR(50) | message, task_created, task_completed, task_failed, agent_online, agent_offline, project_update, alert, handoff, patrol |
| agent_id | VARCHAR(100) FK | Agent |
| division | VARCHAR(50) | Division |
| details | JSONB | Event details |

### projects

Project tracking with heat scoring (0-10 priority).

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Project ID |
| name | VARCHAR(500) | Project name |
| heat | INTEGER | Priority score (0-10) |
| tier | VARCHAR(20) | Project tier |
| status | VARCHAR(20) | active, paused, completed, archived |
| division | VARCHAR(50) | Owning division |
| assigned_agent | VARCHAR(100) FK | Lead agent |
| revenue | BOOLEAN | Revenue-generating? |

### critic_reviews

VETO/approve decisions by critic agents.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Review ID |
| task_id | UUID FK | Reviewed task |
| critic_agent_id | VARCHAR(100) FK | Critic agent |
| decision | VARCHAR(20) | "approve" or "veto" |
| reason | TEXT | Explanation |
| chain_name | VARCHAR(100) | Critic chain used |
| layer_index | INTEGER | Layer in the chain |

### Other Core Tables

- **preferences** — Agent/user preferences (key-value with versioning)
- **audit_log** — Action audit trail
- **integrations** — External service credentials (encrypted)
- **metrics** — Internal system metrics
- **foundry_tools** — Crystallized tools (learned from agent behavior)
- **memory_sync_log** — File-to-DB sync tracking
- **routing_decisions** — Agent routing outcome tracking

---

## Business Tables (02-business-schema.sql)

### leads

CRM lead management with scoring.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Lead ID |
| name | VARCHAR(500) | Contact name |
| email | VARCHAR(500) | Email |
| company | VARCHAR(500) | Company |
| source | VARCHAR(100) | organic, referral, paid, cold_outreach, inbound, partner, event |
| score | INTEGER | Lead score (0-100) |
| pipeline_status | VARCHAR(50) | new, contacted, qualified, nurturing, opportunity, converted, lost, disqualified |
| assigned_agent | VARCHAR(100) FK | Handling agent |

### deals

Sales pipeline with stage tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Deal ID |
| lead_id | UUID FK | Source lead |
| name | VARCHAR(500) | Deal name |
| value | DECIMAL(15,2) | Deal value |
| stage | VARCHAR(50) | prospect, discovery, proposal, negotiation, contract, closed_won, closed_lost |
| probability | DECIMAL(5,2) | Win probability (0-100) |
| expected_close_date | DATE | Expected close |

### outreach_log

Multi-channel activity tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Activity ID |
| lead_id | UUID FK | Target lead |
| deal_id | UUID FK | Related deal |
| agent_id | VARCHAR(100) FK | Executing agent |
| activity_type | VARCHAR(50) | email_sent, call_made, linkedin_sent, meeting_scheduled, proposal_sent, follow_up |
| channel | VARCHAR(50) | email, phone, linkedin, slack, telegram, in_person, video_call |
| outcome | VARCHAR(50) | pending, replied, no_response, interested, not_interested, bounced, completed |

### campaigns

Marketing campaign tracking with ROI.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Campaign ID |
| name | VARCHAR(500) | Campaign name |
| type | VARCHAR(50) | paid_media, email_sequence, content, social, event, referral |
| budget | DECIMAL(12,2) | Budget |
| spend | DECIMAL(12,2) | Actual spend |
| impressions | INTEGER | Impressions |
| clicks | INTEGER | Clicks |
| conversions | INTEGER | Conversions |
| revenue | DECIMAL(12,2) | Revenue generated |
| roi | DECIMAL(8,4) | Return on investment |

### suppliers

E-commerce supplier management with ratings.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Supplier ID |
| name | VARCHAR(500) | Supplier name |
| moq | INTEGER | Minimum order quantity |
| lead_time_days | INTEGER | Lead time |
| rating_quality | INTEGER | Quality rating (1-5) |
| rating_price | INTEGER | Price rating (1-5) |
| rating_reliability | INTEGER | Reliability rating (1-5) |

### products

Inventory management.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Product ID |
| sku | VARCHAR(100) UNIQUE | SKU |
| supplier_id | UUID FK | Supplier |
| unit_cost | DECIMAL(12,2) | Unit cost |
| retail_price | DECIMAL(12,2) | Retail price |
| margin_pct | DECIMAL(6,2) | Margin percentage |
| stock_quantity | INTEGER | Current stock |
| reorder_point | INTEGER | Reorder threshold |

### revenue

Aggregate revenue tracking by vertical.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Revenue ID |
| vertical | VARCHAR(50) | trading, ecommerce, lead_gen, funding, cre, consulting, other |
| period_type | VARCHAR(20) | daily, weekly, monthly, quarterly, annual |
| gross_revenue | DECIMAL(15,2) | Gross revenue |
| costs | DECIMAL(15,2) | Costs |
| net_revenue | DECIMAL(15,2) | Generated column (gross - costs) |

### trading_positions

Portfolio and position tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Position ID |
| symbol | VARCHAR(20) | Ticker symbol |
| side | VARCHAR(10) | long or short |
| quantity | DECIMAL(20,8) | Position size |
| entry_price | DECIMAL(20,8) | Entry price |
| current_price | DECIMAL(20,8) | Current price |
| stop_loss | DECIMAL(20,8) | Stop-loss level |
| take_profit | DECIMAL(20,8) | Take-profit level |
| pnl | DECIMAL(20,2) | Profit/loss |
| platform | VARCHAR(100) | Trading platform |
| status | VARCHAR(20) | open, closed, pending, cancelled |

### competitors

Competitive intelligence targets.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Competitor ID |
| name | VARCHAR(500) | Company name |
| slug | VARCHAR(200) UNIQUE | URL slug |
| verticals | TEXT[] | Business verticals |
| priority | VARCHAR(20) | high, medium, low |
| strengths | TEXT[] | Known strengths |
| weaknesses | TEXT[] | Known weaknesses |

### competitor_changes

AI-analyzed change detection.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Change ID |
| competitor_id | UUID FK | Competitor |
| change_type | VARCHAR(50) | pricing, product, strategic, content, hiring, partnership |
| significance_score | INTEGER | 1-10 |
| summary | TEXT | Change summary |
| impact | TEXT | Business impact |
| recommended_action | TEXT | Suggested response |
| analyzed_by | VARCHAR(100) FK | Analyzing agent |

### scan_history

Prospecting scan tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Scan ID |
| agent_id | VARCHAR(100) FK | Agent |
| source | VARCHAR(100) | Data source |
| query | TEXT | Search query |
| result_count | INTEGER | Results found |
| new_prospects | INTEGER | New prospects identified |
| status | VARCHAR(50) | pending, running, completed, failed, cancelled |

---

## Discord Tables (03-discord-threads.sql)

### discord_thread_messages

Tracks agent messages within task Discord threads.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Message ID |
| task_id | UUID FK | Parent task |
| discord_thread_id | VARCHAR(100) | Thread ID |
| discord_message_id | VARCHAR(100) | Discord message ID |
| agent_id | VARCHAR(100) FK | Posting agent |
| message_type | VARCHAR(50) | work_update, question, handoff, status, completion_summary, veto, approval |
| content | TEXT | Message content |

### task_archive

Completed tasks archived after the cooldown period (36 hours default).

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PK | Archive ID |
| original_task_id | UUID | Original task ID |
| agent_id | VARCHAR(100) | Agent |
| lead_agent | VARCHAR(100) | Lead agent |
| name | VARCHAR(500) | Task name |
| completion_summary | TEXT | Final summary |
| discord_thread_id | VARCHAR(100) | Thread ID |
| thread_message_count | INTEGER | Messages in thread |
| archived_at | TIMESTAMPTZ | Archive time |

---

## Utility Functions

### estimate_tokens(text)

Rough token estimation: ~4 characters = 1 token.

### cleanup_old_context(retention_days)

Archives conversations older than `retention_days` (default 90). Deletes conversations older than `retention_days * 2`.

### auto_archive_bloated_conversations()

Archives conversations that exceed the CRITICAL token threshold (150K tokens).

## Views

### session_context_size

Shows estimated token usage per active conversation:

| Column | Description |
|--------|-------------|
| conversation_id | Conversation UUID |
| title | Conversation title |
| message_count | Total messages |
| estimated_tokens | Estimated token count |
| status | OK, WARNING (>100K), CRITICAL (>150K) |

---

## Additional Storage Systems

Beyond PostgreSQL, The Foundation uses several other storage backends for its 5-tier memory architecture. See [Memory Architecture](memory-architecture.md) for the full picture.

### GraphMem (SQLite)

Graph-based knowledge store at `mcp-servers/graphmem/clawd_brain.db`.

**Tables:**

| Table | Description |
|-------|-------------|
| `entities` | Knowledge graph nodes (agents, projects, concepts, tools) |
| `relationships` | Weighted edges between entities (0-1 scale) |
| `memories` | Stored memories with temporal validity |
| `clusters` | Entity groupings |

**Features:**
- Entity extraction from text
- Relationship weight decay (Ebbinghaus forgetting curve)
- PageRank importance scoring
- Entity consolidation (merge duplicates at 0.85 similarity)
- Auto-pruning of edges below 0.01 weight

MCP tools: `graphmem_ingest`, `graphmem_query`, `graphmem_evolve`, `graphmem_update`

### Beads (JSONL)

Task dependency graph at `.beads/beads.jsonl`. Git-tracked.

**Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | string | Task ID (bd-NNN) |
| title | string | Task description |
| status | string | pending, in-progress, completed, blocked |
| blocks | string[] | Tasks this blocks |
| blocked_by | string[] | Tasks blocking this |
| assigned_to | string | Agent name |
| created_at | ISO8601 | Creation time |
| closed_at | ISO8601 | Completion time |
| summary | string | Completion notes |

CLI: `scripts/bd.sh` (commands: ready, show, create, update, close, sync)

Syncs to PostgreSQL `tasks` table via `scripts/beads-sync-pg.sh`.

### Agent File Memory (Filesystem)

Per-agent memory files at `agents/<name>/`:

| File | Description |
|------|-------------|
| `SOUL.md` | Identity, personality, capabilities, boundaries |
| `MEMORY.md` | Persistent preferences, context, routing patterns |
| `DECISIONS.md` | Logged architectural decisions with rationale |
| `workspace/*.md` | Working documents (templates, drafts, proposals) |

### Cartographer Output (Filesystem)

Codebase structure map at `docs/CODEBASE_MAP.md`. Generated by `scripts/cartographer.sh`.

Contents: directory tree, file counts, agent inventory, config listing, script inventory, MCP server catalog, dependency graph, Docker service map, summary statistics.

### Learnings Log (Filesystem + PostgreSQL)

Session learnings at `.learnings/LEARNINGS.md`. Each entry has a structured ID (LEARN-YYYYMMDD-NNN) and is also inserted into the PostgreSQL `insights` table with a 24-hour TTL.

### Foundation Router (In-Memory + PostgreSQL)

Outcome-tracked agent routing at `foundation-router/`.

| Component | Storage | Description |
|-----------|---------|-------------|
| Agent profiles | In-memory | 14 profiles with keywords, intents, multipliers |
| Routing decisions | PostgreSQL (`routing_decisions`) | Historical routing outcomes |
| Outcome multipliers | In-memory (persisted to PG) | 0.7x-1.3x per agent, rolling 5000 records |
