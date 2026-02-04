# Memory Architecture

The Foundation implements a 5-tier memory hierarchy that gives agents persistent knowledge, contextual awareness, and learning capabilities across sessions. Each tier is optimized for different access patterns, latencies, and data lifetimes.

## Overview

```
L1  Hot Memory         (filesystem, <1ms, eager)     SOUL.md, MEMORY.md, DECISIONS.md
L2  Warm Memory        (hybrid, <100ms, on-demand)   GraphMem, QMD document search
L3  Business Intel     (PostgreSQL, <50ms, on-demand) tasks, facts, insights, leads, deals
L4  Archive            (cloud/PG, <500ms, on-demand)  transcript archive, SuperMemory
L5  Code Structure     (filesystem, <200ms, on-demand) Cartographer codebase map
```

## Tier Details

### L1: Hot Memory

Always loaded at session start. Core identity and context files that define who the agent is and how it should behave.

| Source | Description | Load |
|--------|-------------|------|
| `SOUL.md` | Agent identity, personality, capabilities, boundaries | Eager |
| `USER.md` | User preferences, timezone, mission | Eager |
| `IDENTITY.md` | Core identity | Eager |
| `MEMORY.md` | Per-agent persistent memory (preferences, routing patterns) | On context request |
| `DECISIONS.md` | Per-agent decision log with rationale | On context request |

**Location:** `agents/<agent-name>/`

**Latency:** <1ms (local filesystem)

**TTL:** None (permanent until manually updated)

**Session initialization rule:** Load only SOUL.md, USER.md, and IDENTITY.md eagerly. MEMORY.md and session history are pulled on-demand via `memory_search()` to minimize token usage.

### L2: Warm Memory

Business knowledge via graph and document search. Queried on demand when agents need factual context.

#### GraphMem — Graph Knowledge Store

A graph-based knowledge system built on SQLite, exposed as an MCP server.

**Storage:** `mcp-servers/graphmem/clawd_brain.db`

**Components:**
- **Entities** — nodes in the knowledge graph (agents, projects, concepts, tools, companies)
- **Relationships** — weighted edges between entities (0-1 scale with decay)
- **Memories** — stored observations with temporal validity
- **Clusters** — entity groupings for related concepts

**MCP Tools:**

| Tool | Description |
|------|-------------|
| `graphmem_ingest` | Extract entities and relationships from text |
| `graphmem_query` | Query entities, relationships, memories, or subgraphs |
| `graphmem_evolve` | Run Ebbinghaus decay, PageRank importance, consolidation |
| `graphmem_update` | Update existing entities or relationships |

**Evolution:**
- Runs daily at 3 AM UTC via `scripts/graphmem-evolve-cron.sh`
- **Ebbinghaus forgetting curve** — relationship weights decay over time based on base stability (30 days) and reinforcement bonus (1.5x)
- **PageRank importance** — entities scored by connectivity (damping 0.85, 20 iterations)
- **Consolidation** — near-duplicate entities merged at 0.85 similarity threshold
- **Pruning** — edges below 0.01 weight are removed

**Seeding scripts:**
- `scripts/seed-graphmem-entities.sh` — seeds 14 agents, 5 divisions, 6 system components
- `scripts/seed-graphmem-decisions.sh` — seeds architectural decisions

**Configuration:** `config/graphmem-evolution.json`

#### QMD — Document Search

Local hybrid search engine (BM25 + vector) for business documents. Runs entirely on-device with no external API calls.

**Status:** Configured, pending installation

**Collections:**
- `agent-workspaces` — agent working documents
- `shared-memory` — cross-agent knowledge
- `documentation` — project documentation

**Models:**
- `bge-small-en-v1.5` — embedding model
- `embedding-gemma-300M` — alternative embeddings
- `qwen3-reranker-0.6b` — re-ranking
- `qmd-query-expansion-1.7B` — query expansion

**MCP Tools:** `qmd_query` (hybrid/keyword/semantic search), `qmd_fetch` (document retrieval)

### L3: Business Intel

PostgreSQL structured data for operational queries. The primary persistence layer for all agent activity.

**Key Tables:**

| Table | Description |
|-------|-------------|
| `preferences` | Agent/user preferences (key-value, versioned) |
| `facts` | Knowledge triples with confidence scores and temporal validity |
| `tasks` | Task lifecycle tracking (preflight through archival) |
| `insights` | Agent learnings with TTL (default 1 hour) |
| `activities` | Event feed (task_created, agent_online, alert, patrol, etc.) |
| `projects` | Project tracking with heat scoring (0-10) |
| `routing_decisions` | Foundation Router outcome tracking |
| `conversations` | Session context and summaries |
| `messages` | Message history with tool calls |
| `entities` | Knowledge graph nodes |
| `relationships` | Entity relationships |

**Business tables:** leads, deals, outreach_log, campaigns, suppliers, products, revenue, trading_positions, competitors, competitor_changes, scan_history

**Latency:** <50ms

See [Database Schema](database-schema.md) for the full table reference.

### L4: Archive

Long-term storage for historical context.

#### Transcript Archive

90-day searchable conversation transcripts stored in PostgreSQL. Used for "what happened yesterday" and "what did I do last week" queries.

Backed by the `conversations` and `messages` tables with a 90-day retention policy. The `cleanup_old_context()` function archives stale conversations and deletes those older than 2x the retention period.

#### SuperMemory

Cloud-synced document archive for cross-session persistence.

**Status:** Future implementation

**Latency:** <500ms

### L5: Code Structure

Codebase knowledge via automated mapping.

#### Cartographer

Generates a structural analysis of the codebase as a markdown document.

**Script:** `scripts/cartographer.sh`

**Output:** `docs/CODEBASE_MAP.md`

**Contents:**
- Directory tree (2 levels deep)
- File counts by category
- Agent SOUL.md inventory with division mapping
- Configuration file listing with line counts
- Script inventory with descriptions
- MCP server catalog
- Test file listing
- Dependency graph
- Docker Compose service inventory
- Summary statistics

**TTL:** 24 hours (regenerated daily via `scripts/cartographer-cron.sh`)

**Configuration:** `config/patrol-cartographer.yml`

## Query Routing

When an agent needs information, the query is automatically routed to the appropriate tier based on pattern matching.

| Query Pattern | Tier | Source |
|---------------|------|--------|
| "where is X implemented" | L5 | Cartographer |
| "how does X work" | L5 | Cartographer |
| "what did we decide about X" | L2 | GraphMem |
| "why did we choose X" | L2 | GraphMem |
| "find docs about X" | L2 | QMD |
| "who offered X" | L3 | PostgreSQL |
| "task status / sprint progress" | L3 | PostgreSQL |
| "what happened yesterday" | L4 | Transcript Archive |
| "who am I / what is my role" | L1 | SOUL.md |
| "what are my preferences" | L1 | MEMORY.md |

**Cascade:** If the primary tier returns no results, the system tries the next tier in sequence: L1 -> L2 -> L3 -> L4 -> L5.

**Fallback:** Unmatched queries default to L3 (PostgreSQL).

**Configuration:** `config/memory-query-routing.json`

## Beads — Task Dependency Graph

Beads is a lightweight task management system stored as JSONL. It tracks task dependencies and is git-tracked for version control.

**Storage:** `.beads/beads.jsonl`

**CLI:** `scripts/bd.sh`

| Command | Description |
|---------|-------------|
| `bd ready` | Show tasks with no unmet blockers |
| `bd show <id>` | Task details |
| `bd create "title"` | Create new task |
| `bd update <id> --status <s>` | Update task status |
| `bd close <id> --summary "..."` | Complete task with notes |
| `bd sync` | Git commit beads.jsonl |

**Options:**
- `--blocks <id>` — this task blocks another
- `--discovered-from <id>` — link to parent task

**Sync:** `scripts/beads-sync-pg.sh` syncs beads to the PostgreSQL `tasks` table using `metadata->>'bead_id'` for idempotent upserts.

## Foundation Router

Outcome-tracked agent routing engine. Learns from past performance to improve future routing decisions.

**Location:** `foundation-router/`

### Components

**Agent Profiles** (`agent-profiles.ts`)
- 14 agent profiles with weighted keywords (0.4-0.9)
- Intent matching (task types each agent handles)
- Negative keywords (anti-patterns to avoid misrouting)
- Per-agent outcome multipliers (0.7x-1.3x)

**Scoring Engine** (`scoring-engine.ts`)
- 5-signal scoring algorithm:
  1. Keyword matching (weighted TF-IDF)
  2. Intent matching
  3. Negative keyword penalties
  4. Alias recognition
  5. Outcome multiplier (learned)
- Score threshold: 0.15 (below falls back to Seldon)

**Outcome Tracker** (`outcome-tracker.ts`)
- Records every routing decision with outcome (success/failure)
- Computes per-agent success multipliers (minimum 5 decisions required)
- Rolling window of 5,000 records
- Multiplier range: 0.7x-1.3x
- Debounced PostgreSQL saves (10s interval)

**Convex Bridge** (`convex-bridge.ts`)
- Polls PostgreSQL `messages` table for unrouted entries
- Routes messages above score threshold
- Falls back to Seldon for low-confidence routing
- Tracks processed message IDs (max 10K in-memory)

## Session Hooks

Automated context loading and persistence at session boundaries.

**Configuration:** `config/session-hooks.json`

### Pre-Session (`scripts/session-start.sh`)

Runs at agent startup:
1. Load last 5 non-expired insights from `insights` table
2. Load last 10 activities from `activities` table
3. Show open tasks (pending/in_progress)
4. Show active conversations

**Agent overrides:**
- **Seldon:** includes fleet status
- **Daneel:** includes infrastructure health
- **Venabili:** includes task summary

### Post-Session (`scripts/session-end.sh`)

Runs at session end:
1. Capture session observations
2. Write to `.learnings/LEARNINGS.md` with structured ID (LEARN-YYYYMMDD-NNN)
3. Insert into PostgreSQL `insights` table with 24-hour TTL
4. Log activity to `activities` table

## Memory MCP Server

PostgreSQL-backed memory server exposed via MCP.

**Location:** `mcp-servers/memory/`

**MCP Tools:**

| Tool | Description |
|------|-------------|
| `memory_store` | Store preference, fact, or context entry |
| `memory_retrieve` | Retrieve by type/category/key |
| `memory_search` | Keyword search across all memory types |
| `memory_delete` | Delete by UUID |
| `memory_list` | List grouped by category |

**MCP Resources:**

| URI | Description |
|-----|-------------|
| `memory://preferences` | All stored preferences |
| `memory://context/current` | Active conversation contexts |
| `memory://facts/{category}` | Facts filtered by category |

## Integration Map

```
L1 (SOUL.md, MEMORY.md)
  |
  +-- Loaded at session start via session-hooks
  |
L2 (GraphMem)
  |
  +-- MCP tools: graphmem_ingest/query/evolve
  +-- Evolved daily via cron
  +-- Seeded with agents, divisions, decisions
  |
L3 (PostgreSQL)
  |
  +-- Memory MCP server: memory_store/retrieve/search
  +-- Seldon Protocol: tasks, workflows, agents, handoffs
  +-- Foundation Router: routing_decisions
  +-- Session hooks: insights, activities, learnings
  +-- Beads sync: task graph -> tasks table
  |
L4 (Archive)
  |
  +-- Conversation + message history (90-day retention)
  +-- cleanup_old_context() for garbage collection
  |
L5 (Cartographer)
  |
  +-- Generated by scripts/cartographer.sh
  +-- Refreshed daily via cron
  +-- Output: docs/CODEBASE_MAP.md
```

All tiers feed into PostgreSQL as the single source of truth, with GraphMem providing the graph knowledge layer and session hooks ensuring context continuity across agent sessions.
