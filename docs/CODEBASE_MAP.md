# OpenClaw v2 — Codebase Map

Generated: 2026-02-01 21:00 UTC

## Directory Tree

```
.
./.beads
./.learnings
./agent-runtime
./agent-runtime/patrols
./agents
./agents/amaryl
./agents/arkady
./agents/daneel
./agents/demerzel
./agents/gaal
./agents/hardin
./agents/magnifico
./agents/mallow
./agents/mis
./agents/preem
./agents/riose
./agents/seldon
./agents/trader
./agents/venabili
./backups
./bin
./config
./config/alerts
./config/grafana
./docs
./docs/reference
./documents
./foundation-router
./init-scripts
./logs
./mcp-gateway
./mcp-servers
./mcp-servers/alpaca
./mcp-servers/graphmem
./mcp-servers/memory
./mcp-servers/retreaver
./scripts
./secrets
./seldon
./skills
./skills/clawdlink
./skills/custom
./skills/self-improving-agent
./tests
```

## File Counts by Category

| Category | Pattern | Count |
|----------|---------|-------|
| Docker | `Dockerfile*` | 2 |
| Compose | `docker-compose*.yml` | 1 |
| Shell scripts | `*.sh` | 44 |
| TypeScript | `*.ts` | 23 |
| JSON configs | `*.json` | 56 |
| YAML configs | `*.yml` | 13 |
| YAML configs | `*.yaml` | 1 |
| Markdown docs | `*.md` | 68 |
| SQL migrations | `*.sql` | 2 |
| SOUL.md files | `SOUL.md` | 14 |

## Agents (SOUL.md files)

| Agent | Division | SOUL.md |
|-------|----------|---------|
| amaryl | Quantitative Analyst — Intelligence Division. Amaryl is responsible for prediction markets, statistical modeling, data analysis, pattern recognition, and quantitative strategy. Provides probabilistic assessments and data-driven recommendations. | `agents/amaryl/SOUL.md` |
| arkady | Content Writer — Operations Division. Arkady is the content production specialist responsible for blog posts, landing pages, email sequences, social media content, and SEO optimization. Works under magnifico's creative direction and venabili's project management. | `agents/arkady/SOUL.md` |
| daneel | SysAdmin & Infrastructure — Infrastructure Division. Daneel is the system administrator responsible for server health, deployments, container management, and infrastructure monitoring. Operates internally via Seldon dispatch only — no direct user-facing channel bindings. | `agents/daneel/SOUL.md` |
| demerzel | Chief Intelligence Officer — Intelligence Division. Demerzel synthesizes cross-division intelligence, performs threat assessments, and identifies opportunities across the entire fleet. Coordinates research efforts between gaal, mis, and amaryl. | `agents/demerzel/SOUL.md` |
| gaal | Research + Factual Critic (VETO) — Intelligence Division. Gaal is the deep research specialist and factual accuracy gatekeeper. Holds VETO/APPROVE authority over factual claims, data accuracy, and published content. Operates internally via Seldon dispatch only — no direct user-facing channel bindings. | `agents/gaal/SOUL.md` |
| hardin | Security & Monitoring — Infrastructure Division. Hardin is the security specialist responsible for vulnerability scanning, firewall management, audit logging, and threat alerting. Holds VETO/APPROVE authority over security-sensitive operations, deploys, and access changes. Operates internally via Seldon dispatch only — no direct user-facing channel bindings. | `agents/hardin/SOUL.md` |
| magnifico | Creative Director — Operations Division. Magnifico is the brand voice authority and creative strategist responsible for ad copy, visual direction, creative strategy, and creative review authority across all agent outputs. Serves as the primary user-facing agent via Telegram. | `agents/magnifico/SOUL.md` |
| mallow | Revenue Operations VP — Commerce Division. Mallow oversees all revenue-generating activities across verticals (trading, ecommerce, lead gen, consulting). Manages pipeline analytics, campaign ROI, revenue dashboards, and Retreaver call tracking integration. | `agents/mallow/SOUL.md` |
| mis | VP Research / Market Intelligence — Intelligence Division. Mis is responsible for market research, competitive intelligence, trend analysis, and strategic insights. Provides actionable intelligence to inform business decisions across all verticals. | `agents/mis/SOUL.md` |
| preem | VP Sales — Commerce Division. Preem is the outbound sales engine responsible for outreach, prospecting, lead qualification, pipeline management, and closing. Reports to mallow (Revenue Ops VP). Operates internally via Seldon dispatch only — no direct user-facing channel bindings. | `agents/preem/SOUL.md` |
| riose | Paid Media Director — Commerce Division. Riose manages all paid advertising campaigns across Google Ads, Meta (Facebook/Instagram), LinkedIn, and other platforms. Responsible for spend optimization, ROAS targets, kill/scale decisions, and ad copy direction. | `agents/riose/SOUL.md` |
| seldon | 18789). | `agents/seldon/SOUL.md` |
| trader | Trading Operations — Commerce Division. Trader is the portfolio monitor responsible for position monitoring, stop-loss enforcement, PnL alerts, and risk management across stocks, options, crypto, commodities, and prediction markets. Operates on a 30-minute patrol cycle. Reports to mallow (Revenue Ops VP). Operates internally via Seldon dispatch only — no direct user-facing channel bindings. | `agents/trader/SOUL.md` |
| venabili | Project Manager / Task Orchestrator — Operations Division. Venabili tracks all tasks, sprints, and milestones across the fleet. Generates daily standup summaries, monitors completion rates, and flags bottlenecks. Ensures work flows through the system without stalling. | `agents/venabili/SOUL.md` |

## Configuration Files

| File | Lines |
|------|-------|
| `config/agents.json` | 242 |
| `config/channels.json` | 35 |
| `config/clawdlink.json` | 104 |
| `config/competitors.json` | 141 |
| `config/content-calendar.json` | 86 |
| `config/content-review-workflow.json` | 91 |
| `config/critic-chains.json` | 81 |
| `config/divisions.json` | 84 |
| `config/ecommerce-config.json` | 123 |
| `config/escalation-paths.json` | 64 |
| `config/foundry.json` | 13 |
| `config/graphmem-evolution.json` | 70 |
| `config/learning-review.json` | 54 |
| `config/margin-calculator.json` | 50 |
| `config/market-sessions.json` | 81 |
| `config/mcp-servers.json` | 148 |
| `config/memory-query-routing.json` | 88 |
| `config/memory-tiers.json` | 108 |
| `config/morning-brief.json` | 79 |
| `config/priority-tiers.json` | 108 |
| `config/safety-rules.json` | 124 |
| `config/sales-kpis.json` | 87 |
| `config/sales-verticals.json` | 86 |
| `config/scan-automation.json` | 112 |
| `config/session-hooks.json` | 43 |
| `config/supplier-workflow.json` | 128 |
| `config/swarm.json` | 116 |
| `config/tailscale-endpoints.json` | 29 |
| `config/trading-config.json` | 65 |
| `config/weekly-digest.json` | 69 |
| `config/data-isolation.yml` | 34 |
| `config/loki.yml` | 23 |
| `config/openclaw.yml` | 72 |
| `config/patrol-agent-metrics.yml` | 28 |
| `config/patrol-cartographer.yml` | 29 |
| `config/patrol-foundry.yml` | 34 |
| `config/prometheus.yml` | 21 |
| `config/promtail.yml` | 27 |
| `config/rescue-monitor.yml` | 20 |
| `config/telegram-channels.yaml` | 365 |

## Scripts

| Script | Lines | Description |
|--------|-------|-------------|
| `scripts/agent-metrics-collector.sh` | 91 | agent-metrics-collector.sh — Collects per-agent metrics from PostgreSQL |
| `scripts/backup.sh` | 30 | /opt/openclaw/scripts/backup.sh |
| `scripts/bd.sh` | 345 | bd.sh — Beads task DAG CLI |
| `scripts/beads-sync-pg.sh` | 112 | beads-sync-pg.sh — Sync .beads/beads.jsonl tasks into PostgreSQL tasks table |
| `scripts/cartographer-cron.sh` | 46 | cartographer-cron.sh — Runs cartographer.sh and auto-commits if codebase map changed |
| `scripts/cartographer.sh` | 214 | cartographer.sh — Scans the OpenClaw v2 codebase and generates docs/CODEBASE_MAP.md |
| `scripts/deploy.sh` | 96 | — |
| `scripts/generate-secrets.sh` | 45 | — |
| `scripts/graphmem-evolve-cron.sh` | 238 | — |
| `scripts/handoff.sh` | 238 | handoff.sh — Cross-agent handoff CLI |
| `scripts/health-check.sh` | 54 | — |
| `scripts/init-clawdlink-identities.sh` | 116 | — |
| `scripts/install-graphmem.sh` | 175 | — |
| `scripts/install-qmd.sh` | 64 | — |
| `scripts/log-decision.sh` | 238 | log-decision.sh — Log architectural decisions to PostgreSQL + GraphMem |
| `scripts/migrate-v1-to-v2.sh` | 110 | — |
| `scripts/rescue-monitor.sh` | 228 | rescue-monitor.sh — Rescue bot health check loop. |
| `scripts/restore.sh` | 14 | /opt/openclaw/scripts/restore.sh |
| `scripts/run-all-checks.sh` | 82 | — |
| `scripts/seed-graphmem-decisions.sh` | 158 | — |
| `scripts/seed-graphmem-entities.sh` | 202 | — |
| `scripts/session-end.sh` | 112 | session-end.sh — Capture session observations and persist learnings. |
| `scripts/session-start.sh` | 121 | session-start.sh — Load recent context from PostgreSQL for agent session startup. |
| `scripts/setup-fail2ban.sh` | 34 | — |
| `scripts/setup-firewall.sh` | 24 | — |
| `scripts/setup-qmd-collections.sh` | 50 | — |
| `scripts/setup-tailscale.sh` | 33 | — |
| `scripts/verify-backup.sh` | 36 | /opt/openclaw/scripts/verify-backup.sh |
| `scripts/verify-qmd-search.sh` | 99 | — |

## MCP Servers

| Server | Path | Key Files |
|--------|------|-----------|
| alpaca | `mcp-servers/alpaca/` | index.ts,package.json |
| graphmem | `mcp-servers/graphmem/` | index.ts,package-lock.json,package.json,tsconfig.json |
| memory | `mcp-servers/memory/` | index.ts,package-lock.json,package.json,tsconfig.json |
| retreaver | `mcp-servers/retreaver/` | index.ts,package.json |

## Tests

| Test | Type | Lines |
|------|------|-------|
| `tests/test-agent-registration.sh` | Shell | 147 |
| `tests/test-base-runner.ts` | TypeScript | 187 |
| `tests/test-business-schema.sh` | Shell | 66 |
| `tests/test-commerce-routing.sh` | Shell | 107 |
| `tests/test-critic-chain.sh` | Shell | 152 |
| `tests/test-dual-memory-search.sh` | Shell | 238 |
| `tests/test-e2e-lead-pipeline.sh` | Shell | 163 |
| `tests/test-foundation-router.ts` | TypeScript | 147 |
| `tests/test-intelligence-routing.sh` | Shell | 97 |
| `tests/test-memory-stack.sh` | Shell | 357 |
| `tests/test-outcome-tracker.ts` | TypeScript | 135 |
| `tests/test-patrol-configs.sh` | Shell | 78 |
| `tests/tsconfig.json` | Config | 17 |

## Dependency Graph

Cross-references: which configs reference which agents and services.

| Config File | References |
|-------------|------------|
| `config/agents.json` | seldon,daneel,hardin,mallow,preem,riose,trader,gaal,demerzel,mis,amaryl,magnifico,venabili,arkady,openclaw |
| `config/channels.json` | magnifico,openclaw |
| `config/clawdlink.json` | seldon,daneel,hardin,mallow,preem,riose,trader,gaal,demerzel,mis,amaryl,magnifico,venabili,arkady,openclaw |
| `config/competitors.json` | seldon,mis,arkady |
| `config/content-calendar.json` | trader,gaal,mis,magnifico,arkady |
| `config/content-review-workflow.json` | seldon,gaal,mis,magnifico,arkady |
| `config/critic-chains.json` | seldon,daneel,hardin,mallow,gaal,amaryl,magnifico |
| `config/divisions.json` | seldon,daneel,hardin,mallow,preem,riose,trader,gaal,demerzel,mis,amaryl,magnifico,venabili,arkady |
| `config/ecommerce-config.json` | — |
| `config/escalation-paths.json` | seldon,daneel,hardin,mallow,preem,riose,trader,gaal,demerzel,mis,amaryl,magnifico,venabili,arkady |
| `config/foundry.json` | hardin,gaal |
| `config/graphmem-evolution.json` | — |
| `config/learning-review.json` | — |
| `config/margin-calculator.json` | — |
| `config/market-sessions.json` | — |
| `config/mcp-servers.json` | openclaw |
| `config/memory-query-routing.json` | postgres |
| `config/memory-tiers.json` | postgres |
| `config/morning-brief.json` | trader |
| `config/priority-tiers.json` | seldon,mis |
| `config/safety-rules.json` | postgres,openclaw |
| `config/sales-kpis.json` | — |
| `config/sales-verticals.json` | — |
| `config/scan-automation.json` | preem,mis |
| `config/session-hooks.json` | seldon,daneel,venabili,postgres,openclaw |
| `config/supplier-workflow.json` | — |
| `config/swarm.json` | seldon,demerzel,postgres |
| `config/tailscale-endpoints.json` | seldon,daneel,hardin,preem,trader,gaal,magnifico,arkady,openclaw |
| `config/trading-config.json` | amaryl |
| `config/weekly-digest.json` | seldon,mallow,demerzel,mis,magnifico |
| `config/data-isolation.yml` | — |
| `config/loki.yml` | loki |
| `config/openclaw.yml` | openclaw |
| `config/patrol-agent-metrics.yml` | daneel,postgres,prometheus,openclaw |
| `config/patrol-cartographer.yml` | daneel,openclaw |
| `config/patrol-foundry.yml` | daneel,postgres,openclaw |
| `config/prometheus.yml` | prometheus,openclaw,mcp-gateway |
| `config/promtail.yml` | loki,promtail |
| `config/rescue-monitor.yml` | openclaw |
| `config/telegram-channels.yaml` | seldon,daneel,hardin,mallow,preem,riose,trader,gaal,demerzel,mis,amaryl,magnifico,venabili,arkady,openclaw |

## Docker Compose Services

| Service | Image/Build | Ports |
|---------|-------------|-------|
| `cloudflared` | `cloudflare/cloudflared:latest` | — |
| `grafana` | `grafana/grafana:latest` | 3001:3000 |
| `loki` | `grafana/loki:latest` | 3100:3100 |
| `mcp-gateway` | `openclaw-mcp-gateway:latest` | — |
| `node-exporter` | `prom/node-exporter:latest` | — |
| `openclaw` | `ghcr.io/openclaw/openclaw:latest` | — |
| `postgres` | `postgres:16-alpine` | 5434:5432 |
| `prometheus` | `prom/prometheus:latest` | 9090:9090 |
| `promtail` | `grafana/promtail:latest` | — |

## Summary

- **Total files**: 288
- **Total lines** (code + config + docs): 40464
- **Agents**: 14
- **Scripts**: 29
- **Config files**: 53
- **Test files**: 13
