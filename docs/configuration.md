# Configuration

The Foundation uses JSON configuration files in the `config/` directory. This document covers all configuration files and their purpose.

## Configuration Files

| File | Description |
|------|-------------|
| `agents.json` | Agent definitions, model tiers, tools, authority |
| `divisions.json` | Division structure and responsibilities |
| `workflows.json` | Workflow templates and gate definitions |
| `critic-chains.json` | Validation pipeline definitions |
| `escalation-paths.json` | Division escalation chains |
| `channels.json` | Discord/Slack/Telegram channel routing |
| `mcp-servers.json` | MCP server definitions |
| `swarm.json` | Multi-model batch processing |
| `session-hooks.json` | Pre/post session automation |
| `safety-rules.json` | Operational safety constraints |
| `memory-tiers.json` | Memory system architecture (L1-L5) |
| `memory-query-routing.json` | Query routing rules |
| `foundry.json` | Tool crystallization config |
| `sales-kpis.json` | Sales performance metrics |
| `sales-verticals.json` | Sales vertical definitions |
| `revenue-config.json` | Revenue tracking configuration |
| `competitors.json` | Competitive intelligence targets |
| `supplier-workflow.json` | E-commerce supplier management |
| `margin-calculator.json` | Product margin calculations |
| `prometheus.yml` | Prometheus metrics collection |
| `loki.yml` | Loki log aggregation |

---

## agents.json

The primary configuration file. Defines all 14 agents and their capabilities.

### Structure

```json
{
  "agents": {
    "defaults": {
      "model": "claude-sonnet-4-5-20250929",
      "apiBaseUrl": "http://anthropic-router:3333",
      "modelTiers": { ... },
      "modelFallbackChain": ["claude", "free", "openrouter"],
      "routingStrategy": { ... },
      "memory": { ... },
      "sandbox": { ... },
      "hooks": { ... }
    },
    "instances": {
      "seldon": { ... },
      "daneel": { ... },
      ...
    }
  },
  "subagents": {
    "enabled": true,
    "maxConcurrent": 5,
    "spawnMethod": "sessions_spawn",
    "allowedAgents": ["gaal", "arkady", "mis", "amaryl", "demerzel"]
  }
}
```

### Model Tiers

| Tier | Model | Use Case |
|------|-------|----------|
| `claude` | claude-sonnet-4-5 | All agent work (primary) |
| `deepseek_v3` | deepseek-chat | Swarm batch pre-processing |
| `deepseek_r1` | deepseek-reasoner | Deep reasoning batch jobs |
| `grok_fast` | grok-4-1-fast-non-reasoning | Overflow when >200K tokens |
| `grok_reasoning` | grok-4-1-fast-reasoning | Reasoning overflow (2M context) |
| `openai` | gpt-4o | Embeddings and vision |
| `openrouter` | auto | Last-resort fallback |
| `free` | gemini-2.5-pro-exp (via OpenRouter) | Rate-limit overflow |

### Agent Instance Fields

| Field | Type | Description |
|-------|------|-------------|
| `port` | number | Dedicated port (18789-18802) |
| `role` | string | Agent role |
| `modelTier` | string | Primary model tier |
| `overflowTier` | string | Overflow model for large contexts |
| `division` | string | Division membership |
| `location` | string | Deployment location |
| `soulPath` | string | Path to personality file |
| `tools.allow` | string[] | Allowed tools |
| `tools.deny` | string[] | Denied tools |
| `patrol` | object | Automated patrol schedule |
| `authority` | object | VETO configuration |
| `bindings` | array | Communication channel assignments |

---

## divisions.json

Defines the 5 organizational divisions.

```json
{
  "divisions": {
    "command": {
      "label": "Command Division",
      "head": "seldon",
      "agents": ["seldon"],
      "responsibilities": [...]
    },
    ...
  },
  "cross_division": {
    "routing": "All cross-division requests route through Seldon",
    "escalation": "Division head → Seldon → Human"
  }
}
```

---

## workflows.json

Workflow templates for multi-step processes. See [Workflows](workflows.md) for details.

Five templates: `feature_build`, `content_publish`, `sales_outreach`, `security_audit`, `market_intel`.

Also defines gate types and pre-flight format.

---

## critic-chains.json

Validation pipeline definitions for the VETO system. See [Critic Chains](critic-chains.md) for details.

Seven chains: `default`, `security`, `research`, `infrastructure`, `financial`, `content`, `trading`.

---

## escalation-paths.json

Defines how each division escalates issues:

```json
{
  "escalation_chains": {
    "infrastructure": {
      "chain": ["agent", "daneel", "seldon", "human"],
      "security_override": {
        "agent": "hardin",
        "authority": "VETO",
        "escalates_directly_to": "seldon"
      }
    },
    ...
  },
  "human_escalation": {
    "channels": ["telegram_@clawd_ceo", "slack_dm"],
    "auto_timeout_hours": 24,
    "timeout_action": "Re-escalate with increased priority"
  }
}
```

Override rules:
- **Hardin** (security VETO) escalates directly to Seldon, bypassing Daneel
- **Gaal** (factual VETO) escalates directly to Seldon, bypassing Demerzel
- **P0 commerce events** (stop loss breach, revenue emergency) escalate directly to Seldon + human

---

## channels.json

Discord, Slack, and Telegram channel routing configuration. Defines:

- Channel categories per division
- Agent-to-channel routing
- Thread creation rules
- Notification preferences

See [Discord Integration](discord-integration.md) for the full channel structure.

---

## mcp-servers.json

MCP (Model Context Protocol) server definitions. Each entry specifies:

```json
{
  "memory": {
    "command": "node",
    "args": ["/app/mcp-servers/memory/index.js"],
    "env": { "DB_HOST": "postgres" }
  },
  ...
}
```

12 servers: memory, filesystem, brave-search, google-calendar, slack, graphmem, memory-bank, alpaca, retreaver, airtable, qmd, shopify.

---

## swarm.json

Configuration for batch pre-processing using cheap/free models:

- 12 model configurations for parallel batch work
- Rate limits and cost tracking
- Used for bulk research, data processing, and overflow

---

## memory-tiers.json

Five-level memory architecture:

| Level | Storage | Speed | Use Case |
|-------|---------|-------|----------|
| L1 | In-memory | Instant | Active session context |
| L2 | Redis/local | Fast | Recent conversations |
| L3 | PostgreSQL | Medium | Persistent facts and entities |
| L4 | Graph (graphmem) | Medium | Knowledge graph relationships |
| L5 | File system | Slow | Agent personality files, archives |

---

## safety-rules.json

Operational constraints that prevent dangerous actions:

- Maximum spend limits per agent per day
- Prohibited actions (e.g., no production data deletion)
- Required approvals for sensitive operations
- Rate limits for external API calls

---

## Environment Variables

See `.env.example` for the full list. Key sections:

| Section | Variables |
|---------|-----------|
| Database | DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD |
| Seldon | SELDON_PORT, SELDON_HOST |
| Dashboard | DASHBOARD_PORT |
| Discord | DISCORD_BOT_TOKEN, DISCORD_GUILD_ID |
| AI Providers | ANTHROPIC_API_KEY, DEEPSEEK_API_KEY, XAI_API_KEY, OPENAI_API_KEY |
| Integrations | SLACK_BOT_TOKEN, TELEGRAM_BOT_TOKEN, BRAVE_API_KEY |
| Trading | ALPACA_API_KEY, ALPACA_SECRET_KEY |
| Networking | CLOUDFLARE_TUNNEL_TOKEN |
| Observability | GRAFANA_ADMIN_PASSWORD |
