# The Foundation

An open-source multi-agent AI orchestration platform built on [OpenClaw](https://github.com/openclaw). Deploy a team of 14 specialized AI agents that coordinate through a central protocol, execute complex workflows with human-in-the-loop approval gates, and communicate via Discord threads.

**Self-host for free** or use **[Foundation Cloud](https://thefoundation.dev)** — we build, deploy, and manage your agent team for you.

```
                    Human (Discord / Dashboard)
                           |
                     [Approval Gate]
                           |
                    Seldon Protocol
                    /    |    |    \
              Daneel  Hardin  Mis  ... (14 agents)
                |       |      |
              Build   Analyze  Research
                \       |      /
                 [Workflow Engine]
                        |
                   PostgreSQL
```

## What It Does

The Foundation coordinates multiple AI agents as a team. Each agent has a defined role, authority level, and tool access. A central orchestrator (Seldon Protocol) dispatches work, manages dependencies between agents, enforces approval gates, and tracks everything in PostgreSQL. The agents run on [OpenClaw](https://github.com/openclaw) as the underlying agent runtime.

**Key capabilities:**

- **14 specialized agents** across 5 divisions (Command, Infrastructure, Commerce, Intelligence, Operations)
- **Workflow engine** with dependency-based execution, parallel steps, and critic chain vetoes
- **Pre-flight approval gates** — agents propose plans, humans approve before execution begins
- **Task-to-Discord-thread lifecycle** — each task gets a linked Discord thread for real-time collaboration
- **Multi-model routing** — Claude as primary, with overflow to Grok (2M context) and batch processing via DeepSeek
- **Web dashboard** for monitoring agents, tasks, and workflow status

## Architecture

| Component | Technology | Purpose |
|-----------|-----------|---------|
| OpenClaw | Agent Runtime | Core agent execution engine |
| Seldon Protocol | Node.js / TypeScript | Central orchestrator API (port 18789) |
| Dashboard | Node.js HTTP server | Web UI + API proxy (port 18810) |
| Database | PostgreSQL 16 | Task state, agent memory, workflow tracking |
| Agents | Claude (Anthropic) | 14 specialized AI agents |
| Communication | Discord | Human-agent interaction via threads |
| Orchestration | Docker Compose | Service management |
| Observability | Prometheus + Grafana + Loki | Metrics, dashboards, logs |
| Networking | Cloudflare Tunnel | Zero-trust secure access |

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Node.js 20+
- A Discord bot token ([create one here](https://discord.com/developers/applications))
- An Anthropic API key or Claude Max subscription

### 1. Clone and configure

```bash
git clone https://github.com/hdiesel323/openclaw-002.git
cd openclaw-002

# Copy environment template and fill in your values
cp .env.example .env
# Edit .env with your database password, API keys, etc.
```

### 2. Set up secrets

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

### 3. Start services

```bash
docker compose up -d

# Verify everything is healthy
docker compose ps
curl http://localhost:18789/health    # Seldon API
curl http://localhost:18810/health    # Dashboard
```

### 4. Run the schema migration

```bash
cat init-scripts/01-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/02-business-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/03-discord-threads.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
```

### 5. Open the dashboard

Navigate to `http://localhost:18810` to see the Command Center dashboard.

## The Agents

The Foundation ships with 14 agents organized into 5 divisions:

| Division | Agent | Role |
|----------|-------|------|
| **Command** | Seldon | Chief orchestrator, workflow dispatch, approval gates |
| | Daneel | Primary builder, code generation, implementation |
| | Hardin | Strategic planning, architecture decisions |
| **Infrastructure** | Demerzel | Systems architecture, infrastructure design |
| | Amaryl | Testing, verification, quality assurance |
| | Venabili | Security auditing, vulnerability assessment |
| **Commerce** | Magnifico | Customer-facing communication, content |
| | Mallow | Sales strategy, outreach automation |
| | Trader | Financial analysis, market operations |
| **Intelligence** | Mis | Deep research, competitive analysis (2M context overflow) |
| | Gaal | Data analysis, pattern recognition |
| | Riose | Threat assessment, risk analysis |
| **Operations** | Preem | Process automation, operational workflows |
| | Arkady | Monitoring, alerting, incident response |

Each agent has configurable authority levels, tool access, and can participate in critic chains that review other agents' work.

## Workflow System

The Foundation includes 5 built-in workflow templates:

| Workflow | Steps | Purpose |
|----------|-------|---------|
| `feature_build` | Intake > Research > Design > Build > Review > Deploy | Full feature lifecycle |
| `content_publish` | Draft > Edit > Review > Publish | Content creation pipeline |
| `sales_outreach` | Research > Draft > Review > Send > Follow-up | Sales automation |
| `security_audit` | Scan > Analyze > Report > Remediate | Security assessment |
| `market_intel` | Collect > Analyze > Synthesize > Brief | Market research |

### How workflows execute

1. **Preflight** — Seldon creates a plan with intent, risks, and verification criteria
2. **Approval gate** — Human reviews the plan in Discord and approves ("Go") or rejects ("Stop")
3. **Execution** — Steps execute based on dependency graph, with parallel steps running concurrently
4. **Critic chains** — Designated agents review work at configured checkpoints
5. **Completion** — Summary posted to Discord thread, task archived after cooldown

```bash
# Create a preflight plan
curl -X POST http://localhost:18789/seldon/preflight \
  -H 'Content-Type: application/json' \
  -d '{
    "task": "Build user authentication",
    "intent": "Add OAuth2 login flow with refresh tokens",
    "workflow_template": "feature_build",
    "priority": "high"
  }'

# Approve and execute
curl -X POST http://localhost:18789/seldon/preflight/{task_id}/approve \
  -H 'Content-Type: application/json' \
  -d '{"action": "go", "approved_by": "admin"}'
```

## API Reference

### Seldon Protocol (port 18789)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/seldon/status` | System status (agents, tasks, services) |
| GET | `/seldon/tasks` | List all tasks |
| GET | `/seldon/task/:id` | Get task details with thread messages |
| POST | `/seldon/dispatch` | Dispatch task to an agent |
| POST | `/seldon/complete` | Mark task as completed |
| POST | `/seldon/preflight` | Create pre-flight approval request |
| POST | `/seldon/preflight/:id/approve` | Approve/reject pre-flight |
| GET | `/seldon/workflows` | List active workflows |
| GET | `/seldon/workflow/:id` | Get workflow state |
| POST | `/seldon/workflow/:id/gate` | Respond to a workflow gate |

## Configuration

All configuration lives in `config/`:

| File | Purpose |
|------|---------|
| `agents.json` | Agent definitions, model tiers, authority levels, tools |
| `workflows.json` | Workflow templates with steps, dependencies, critic chains |
| `channels.json` | Discord/Slack/Telegram channel configuration |
| `swarm.json` | Multi-model batch processing configuration |
| `safety-rules.json` | Agent safety constraints and guardrails |

## Deployment

### Local (Docker Compose)

The default setup runs everything locally. See [Quick Start](#quick-start) above.

### VPS (Production)

Scripts for deploying to a Hetzner VPS are included:

```bash
# 1. Create and harden the server
./scripts/vps/01-create-server.sh
./scripts/vps/02-harden.sh

# 2. Install Docker
./scripts/vps/03-install-docker.sh

# 3. Deploy
./scripts/vps/04-deploy.sh
```

### Secrets Management

The Foundation supports multiple secrets backends:

- **File-based** (default) — secrets stored in `secrets/*.txt`, mounted as Docker secrets
- **1Password Service Account** — headless secret management via `scripts/op-secrets.sh`
- **Environment variables** — via `.env` file

## Foundation Cloud

Don't want to self-host? **Foundation Cloud** is a managed service where we deploy and run your agent team for you.

| | Self-Hosted (Free) | Starter | Pro | Enterprise |
|---|---|---|---|---|
| **Agents** | 14 (unlimited) | 5 | 14 | Custom |
| **Workflows** | Unlimited | 5 templates | Unlimited | Custom |
| **Infrastructure** | You manage | Managed | Managed | Dedicated |
| **Discord Integration** | DIY setup | Managed | Managed | Managed |
| **Support** | Community | Email | Priority | Dedicated |
| **Price** | Free | $49/mo | $149/mo | Contact us |

[Get started with Foundation Cloud](https://thefoundation.dev)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and PR guidelines.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting and security practices.

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
