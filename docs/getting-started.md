# Getting Started

This guide walks you through installing The Foundation, configuring your environment, and running your first agent workflow.

## Prerequisites

- **Docker** and **Docker Compose** (v2+)
- **Node.js 20+** (for local development)
- **PostgreSQL 16** (provided via Docker, or use your own)
- A **Discord bot token** — [create one here](https://discord.com/developers/applications)
- An **Anthropic API key** or Claude Max subscription

## 1. Clone the Repository

```bash
git clone https://github.com/hdiesel323/the-foundation.git
cd the-foundation
```

## 2. Configure Environment

```bash
cp .env.example .env
```

Open `.env` and fill in the required values. At minimum you need:

| Variable | Description |
|----------|-------------|
| `DB_PASSWORD` | PostgreSQL password |
| `ANTHROPIC_API_KEY` | Your Anthropic API key |
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `DISCORD_GUILD_ID` | Your Discord server ID |

See [Configuration](configuration.md) for the full list of environment variables.

## 3. Set Up Secrets

The Foundation uses Docker secrets for sensitive credentials:

```bash
# Generate placeholder secret files
./scripts/generate-secrets.sh

# Fill in your actual credentials
echo "your-anthropic-api-key" > secrets/anthropic_key.txt
echo "your-discord-bot-token" > secrets/discord_token.txt
echo "your-db-password" > secrets/db_password.txt

# Lock down permissions
chmod 600 secrets/*.txt
```

## 4. Start Services

```bash
docker compose up -d
```

Verify everything is healthy:

```bash
docker compose ps

# Check service health
curl http://localhost:18789/health    # Seldon Protocol API
curl http://localhost:18810/health    # Dashboard
```

Expected output from Seldon:

```json
{ "status": "ok", "service": "seldon-protocol" }
```

## 5. Run Database Migrations

```bash
cat init-scripts/01-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/02-business-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/03-discord-threads.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
```

## 6. Register Your First Agent

```bash
curl -X POST http://localhost:18789/seldon/register \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "seldon",
    "name": "Seldon",
    "role": "Orchestrator",
    "capabilities": ["route", "coordinate", "delegate", "monitor"],
    "status": "online"
  }'
```

## 7. Run Your First Workflow

### Create a pre-flight request

```bash
curl -X POST http://localhost:18789/seldon/preflight \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Write a blog post about AI orchestration",
    "intent": "Create SEO-optimized content about multi-agent systems",
    "plan": [
      "Research competitor content and keywords",
      "Draft 1500-word article with examples",
      "Fact-check all claims",
      "Publish to blog"
    ],
    "verification": "Published URL returns 200, passes Lighthouse SEO audit",
    "risks": ["Factual claims need verification", "SEO keywords may be competitive"],
    "workflow_template": "content_publish",
    "estimated_agents": ["mis", "magnifico", "arkady", "gaal"]
  }'
```

### Approve the pre-flight

```bash
curl -X POST http://localhost:18789/seldon/preflight/<task-id>/approve \
  -H "Content-Type: application/json" \
  -d '{ "action": "go" }'
```

The workflow engine will now execute the `content_publish` workflow, dispatching work to each agent in dependency order.

## 8. Open the Dashboard

Navigate to [http://localhost:18810](http://localhost:18810) in your browser. You'll see:

- **Tasks** — active and completed tasks with priority labels
- **Agents** — registered agents with heartbeat status
- **Workflows** — active workflow executions and step progress
- **Divisions** — agent organization by division

## 9. Set Up Discord

If you configured a Discord bot token, tasks will automatically create threads in your Discord server. See [Discord Integration](discord-integration.md) for channel setup and thread lifecycle details.

## Directory Structure

```
the-foundation/
├── seldon/              # Seldon Protocol API (TypeScript)
├── dashboard/           # Web dashboard (Node.js + HTML)
├── config/              # Agent, workflow, and system configuration
├── init-scripts/        # PostgreSQL schema migrations
├── scripts/             # Operational scripts (backup, deploy, health)
├── agents/              # Agent personality files (SOUL.md, MEMORY.md)
├── mcp-gateway/         # MCP server hub
├── mcp-servers/         # Custom MCP server implementations
├── foundation-router/   # 5-signal agent routing engine
├── site/                # Landing page
├── secrets/             # Docker secrets (gitignored)
├── docker-compose.yml   # Service orchestration
└── .env.example         # Environment template
```

## Next Steps

- [Architecture](architecture.md) — understand how the system fits together
- [Agents](agents.md) — meet the 14 agents and their capabilities
- [Workflows](workflows.md) — learn about workflow templates and execution
- [API Reference](api-reference.md) — full Seldon Protocol endpoint documentation
- [Deployment](deployment.md) — production deployment on VPS
