# Architecture

The Foundation is a multi-agent AI orchestration platform built on the OpenClaw runtime. This document describes how the components fit together.

## System Overview

```
                         Human
                      /         \
                Discord          Dashboard (:18810)
                  |                  |
                  v                  v
            ┌─────────────────────────────┐
            │      Seldon Protocol        │
            │     (Express/TS :18789)     │
            │                             │
            │  Preflight ─► Workflow ─►   │
            │  Dispatch      Engine       │
            │  Handoff     Critic Chains  │
            │  Broadcast   Archival       │
            └──────────┬──────────────────┘
                       │
          ┌────────────┼────────────────┐
          │            │                │
          v            v                v
    ┌──────────┐ ┌──────────┐   ┌────────────┐
    │ Postgres │ │ Discord  │   │ MCP Gateway│
    │   (16)   │ │   API    │   │   (:3000)  │
    └──────────┘ └──────────┘   └────────────┘
                                      │
                              ┌───────┼───────┐
                              │       │       │
                           Memory  Brave   Alpaca
                           Server  Search  Trading
                             ...     ...     ...
```

## Core Components

### Seldon Protocol

The central orchestrator. An Express.js/TypeScript API server running on port 18789.

**Responsibilities:**
- Receive tasks from humans (via Dashboard or Discord)
- Route tasks to appropriate agents based on capabilities
- Execute multi-step workflows with dependency tracking
- Enforce pre-flight approval gates before execution
- Manage agent-to-agent handoffs
- Run critic chain validation (VETO system)
- Track task lifecycle in PostgreSQL
- Create and manage Discord threads per task

**Source:** `seldon/index.ts` (2,500+ lines)

### Dashboard

A lightweight web UI for monitoring and interacting with the system. Node.js HTTP server on port 18810 that serves a single-page HTML application and proxies API requests to Seldon.

**Features:**
- Real-time task monitoring with priority-based coloring
- Agent status and heartbeat tracking
- Workflow visualization and step progress
- Division-based organization view

**Source:** `dashboard/serve.mjs`, `dashboard/index.html`

### PostgreSQL Database

PostgreSQL 16 stores all persistent state:

- **Core tables:** tasks, agents, workflows, handoffs, conversations, messages
- **Knowledge graph:** entities, relationships, facts (subject-predicate-object triples)
- **Business tables:** leads, deals, campaigns, products, revenue, trading positions
- **Intelligence tables:** competitors, competitor changes, scan history
- **Discord tables:** thread messages, task archive

See [Database Schema](database-schema.md) for the full reference.

### MCP Gateway

A hub server (port 3000) that provides agents access to external tools via the Model Context Protocol:

| MCP Server | Purpose |
|------------|---------|
| memory | Session and fact storage |
| filesystem | File operations |
| brave-search | Web search |
| google-calendar | Calendar management |
| slack | Slack messaging |
| graphmem | Graph-based knowledge store |
| memory-bank | Business knowledge queries |
| alpaca | Trading platform API |
| retreaver | Call tracking |
| airtable | Airtable database |
| shopify | E-commerce platform |
| qmd | Hybrid search (BM25 + vector) |

**Source:** `mcp-gateway/server.mjs`

### Anthropic Router

An OAuth proxy (port 3333) for Claude Max subscriptions. All agents route through this instead of hitting the Anthropic API directly. Handles PKCE OAuth flow and automatic token refresh.

### Foundation Router

A 5-signal scoring engine that determines which agent should handle a given task. Evaluates capability match, current load, division affinity, past performance, and availability.

**Source:** `foundation-router/`

## Agent Architecture

The Foundation runs 14 specialized agents organized into 5 divisions. Each agent has:

- **Role** — a defined job function (e.g., "SysAdmin", "VP Sales")
- **Division** — organizational grouping (Command, Infrastructure, Commerce, Intelligence, Operations)
- **Tools** — allowed and denied tool lists
- **Model tier** — which LLM to use (Claude primary, with overflow tiers)
- **Soul file** — personality and behavioral instructions (`SOUL.md`)
- **Port** — dedicated port assignment (18789-18802)

### Division Structure

```
Command (1)          Seldon — orchestrator
Infrastructure (2)   Daneel — sysadmin, Hardin — security (VETO)
Commerce (4)         Mallow — revenue ops, Preem — sales, Riose — paid media, Trader — trading
Intelligence (4)     Demerzel — chief intel, Gaal — fact checker (VETO), Mis — research, Amaryl — quant
Operations (3)       Venabili — PM, Magnifico — creative, Arkady — content writer
```

### Escalation Paths

Each division has a defined escalation chain:

1. **Agent** escalates to **Division Head**
2. **Division Head** escalates to **Seldon**
3. **Seldon** escalates to **Human**

VETO agents (Hardin for security, Gaal for factual accuracy) can bypass the normal chain and escalate directly to Seldon. P0 commerce events (stop loss breach, revenue emergency) also skip the chain.

### Multi-Model Routing

| Tier | Model | Use Case |
|------|-------|----------|
| Primary | Claude Sonnet 4.5 | All agent work (flat-rate Max subscription) |
| Overflow | Grok (2M context) | When input exceeds Claude's 200K limit |
| Swarm | DeepSeek v3/R1 | Batch pre-processing |
| Specialty | GPT-4o | Embeddings and vision tasks |
| Fallback | OpenRouter / Free models | When Claude is rate-limited |

The fallback chain is: Claude → Free (Gemini/Llama) → OpenRouter.

## Task Lifecycle

```
1. Human submits task
        │
2. POST /seldon/preflight
        │
3. Seldon creates Discord thread
        │
4. Human reviews plan ──── "Stop" ───► Cancelled
        │
    "Go" approved
        │
5. Workflow engine starts
        │
6. Steps dispatched to agents (respecting dependencies)
        │
7. Critic chains validate output ──── VETO ───► Return to agent (retry up to 3x)
        │
8. Human gates pause for approval
        │
9. All steps complete
        │
10. Completion summary posted to Discord thread
        │
11. Task archived after 36 hours
```

## Infrastructure

### Docker Services

The full stack runs via Docker Compose with 11 services:

| Service | Image | Port |
|---------|-------|------|
| postgres | postgres:16-alpine | 5434 |
| seldon | openclaw-seldon | 18789 |
| dashboard | node:20-alpine | 18810 |
| anthropic-router | node:20-slim | 3333 |
| mcp-gateway | openclaw-mcp-gateway | 3000 |
| cloudflared | cloudflare/cloudflared | — |
| prometheus | prom/prometheus | 9090 |
| grafana | grafana/grafana | 3001 |
| loki | grafana/loki | 3100 |
| promtail | grafana/promtail | — |
| openclaw | ghcr.io/openclaw/openclaw | — |

### Security Hardening

All containers run with:

- `read_only: true` — read-only root filesystem
- `no-new-privileges` — prevent privilege escalation
- `cap_drop: ALL` — drop all Linux capabilities
- Resource limits (2 CPU, 2GB RAM per container)
- Secrets mounted via Docker secrets (never environment variables)

### Networking

- **Cloudflare Tunnel** provides zero-trust access without exposing ports
- Internal services communicate via the `openclaw-net` Docker network
- Dashboard proxies `/seldon/*` requests to the Seldon container

### Observability

- **Prometheus** collects metrics from all services
- **Grafana** provides dashboards for agent performance, task throughput, and system health
- **Loki + Promtail** aggregate logs from all containers

## Data Flow

### Agent Registration

```
Agent starts → POST /seldon/register → Stored in agents table → Session token returned
Agent sends heartbeat every 5 minutes → POST /seldon/heartbeat → Updates last_heartbeat
```

### Task Dispatch

```
POST /seldon/dispatch → Task created in DB → Discord thread created → Agent notified
Agent works → Posts updates to Discord thread
Agent completes → POST /seldon/complete → Acceptance criteria validated → Archived after 36h
```

### Workflow Execution

```
Preflight approved → Workflow engine loads template → Steps initialized
Ready steps dispatched (respecting depends_on) → Parallel steps run concurrently
Gate steps pause for human → Human responds → Workflow advances
All steps done → Workflow marked complete → Parent task completed
```

### Agent Handoff

```
POST /seldon/handoff → Handoff record created → Target agent notified
GET /seldon/handoffs/:agentId → Agent checks for pending handoffs
Agent processes handoff → Updates handoff status
```
