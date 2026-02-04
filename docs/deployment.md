# Deployment

This guide covers deploying The Foundation in production. The system is designed to run on a VPS with Docker Compose, secured via Cloudflare Tunnel.

## Architecture Options

| Option | Infrastructure | Best For |
|--------|---------------|----------|
| Single VPS | 1 server, Docker Compose | Small teams, personal use |
| Split deployment | Mac Mini (Seldon) + VPS (agents) | Development + production |
| Foundation Cloud | Managed by us | Teams who want zero-ops |

## Single VPS Deployment

### 1. Provision Server

The included VPS scripts target Hetzner Cloud. Run them in order:

```bash
# Create server (CPX41: 8 vCPU, 16GB RAM)
./scripts/vps/01-create-server.sh

# Harden security (UFW, fail2ban, SSH hardening)
./scripts/vps/02-harden.sh

# Install Docker + Docker Compose
./scripts/vps/03-install-docker.sh

# Deploy the stack
./scripts/vps/04-deploy.sh
```

### 2. Security Hardening (02-harden.sh)

The hardening script configures:

- **UFW firewall** — only ports 22, 80, 443 open
- **fail2ban** — brute-force protection for SSH
- **SSH hardening** — disable password auth, root login
- **Automatic security updates**
- **Process accounting**

### 3. Docker Deployment (04-deploy.sh)

```bash
# Clone repo on VPS
git clone https://github.com/hdiesel323/the-foundation.git
cd the-foundation

# Configure environment
cp .env.example .env
vim .env  # Fill in production values

# Set up secrets
./scripts/generate-secrets.sh
# Fill in production credentials in secrets/

# Build and start
docker compose up -d --build

# Run migrations
cat init-scripts/01-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/02-business-schema.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw
cat init-scripts/03-discord-threads.sql | docker exec -i openclaw-postgres psql -U openclaw -d openclaw

# Verify
docker compose ps
curl http://localhost:18789/health
```

## Cloudflare Tunnel

The Foundation uses Cloudflare Tunnel for zero-trust access. No ports need to be exposed publicly.

### Setup

1. Create a tunnel in the [Cloudflare dashboard](https://one.dash.cloudflare.com/)
2. Get the tunnel token
3. Add to `.env`:

```bash
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token
```

4. The `cloudflared` service in Docker Compose handles the connection

### Routing

Configure tunnel routes in the Cloudflare dashboard to point to:

| Public hostname | Service |
|----------------|---------|
| dashboard.yourdomain.com | http://dashboard:18810 |
| api.yourdomain.com | http://seldon:18789 |
| grafana.yourdomain.com | http://grafana:3001 |

## Container Security

All containers run with strict security settings:

```yaml
read_only: true
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
```

## Docker Compose Services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| postgres | postgres:16-alpine | 5434 | Database |
| seldon | openclaw-seldon:latest | 18789 | Orchestrator API |
| dashboard | node:20-alpine | 18810 | Web UI |
| anthropic-router | node:20-slim | 3333 | Claude Max OAuth proxy |
| openclaw | ghcr.io/openclaw/openclaw | — | Agent runtime |
| mcp-gateway | openclaw-mcp-gateway | 3000 | MCP server hub |
| cloudflared | cloudflare/cloudflared | — | Tunnel daemon |
| prometheus | prom/prometheus | 9090 | Metrics |
| grafana | grafana/grafana | 3001 | Dashboards |
| loki | grafana/loki | 3100 | Logs |
| promtail | grafana/promtail | — | Log shipper |

## Secrets Management

Secrets are stored as files in the `secrets/` directory and mounted into containers via Docker secrets. Never use environment variables for credentials in production.

```bash
secrets/
├── anthropic_key.txt
├── db_password.txt
├── discord_token.txt
├── openai_key.txt
├── deepseek_key.txt
├── xai_key.txt
├── slack_bot_token.txt
├── telegram_bot_token.txt
├── alpaca_api_key.txt
├── alpaca_secret_key.txt
├── brave_api_key.txt
└── openrouter_key.txt
```

```bash
# Set proper permissions
chmod 600 secrets/*.txt
```

### 1Password Integration

For teams using 1Password, a script is included to pull secrets:

```bash
./scripts/op-secrets.sh
```

This reads secret references from `.env` and populates the `secrets/` directory.

## Backups

### Automated Backups

```bash
./scripts/backup.sh
```

The backup script:

1. Dumps PostgreSQL to a `.sql` file
2. Compresses with gzip
3. Encrypts with GPG
4. Uploads to Cloudflare R2 (S3-compatible)

### Restore

```bash
./scripts/restore.sh <backup-file>
```

### Backup Schedule

Set up a cron job for automated backups:

```bash
# Daily at 2 AM
0 2 * * * cd /path/to/the-foundation && ./scripts/backup.sh
```

## Health Checks

```bash
./scripts/health-check.sh
```

Checks:

- PostgreSQL connectivity
- Seldon API responding
- Dashboard accessible
- All Docker containers running
- Disk space and memory

## Monitoring

### Prometheus

Access at `http://localhost:9090`. Collects metrics from:

- Seldon API (request counts, latencies)
- PostgreSQL (connections, query performance)
- Docker (container CPU, memory, network)
- Node.js (event loop lag, heap usage)

### Grafana

Access at `http://localhost:3001`. Default credentials: admin / (set via `GRAFANA_ADMIN_PASSWORD`).

Pre-configured dashboards:

- Agent performance (tasks completed, response times)
- Task throughput (tasks per hour, completion rate)
- System health (CPU, memory, disk, network)
- Workflow execution (steps completed, gate wait times)

### Loki

Log aggregation from all containers. Query logs in Grafana using LogQL.

## Scaling

### Vertical Scaling

The simplest approach. Increase VPS resources:

- **8 vCPU / 16GB** — up to 14 agents, moderate load
- **16 vCPU / 32GB** — all agents active, heavy workflows

### Horizontal Scaling

For Foundation Cloud multi-tenant deployment, see [Multi-Tenant Architecture](multi-tenant-architecture.md).

The key architectural decisions for horizontal scaling:

- Schema-per-tenant in PostgreSQL
- Isolated Seldon pods per tenant
- Shared infrastructure layer (Postgres, monitoring)
- Kubernetes on Hetzner for orchestration

## Troubleshooting

### Service won't start

```bash
# Check logs
docker compose logs <service-name>

# Check port conflicts
lsof -i :18789
lsof -i :18810
```

### Database connection errors

```bash
# Verify postgres is healthy
docker compose exec postgres pg_isready

# Check connection params match .env
docker compose exec postgres psql -U openclaw -d openclaw -c "SELECT 1"
```

### Seldon not responding

```bash
# Check container status
docker compose ps seldon

# Check logs for TypeScript errors
docker compose logs seldon --tail 50

# Restart
docker compose restart seldon
```

### Dashboard proxy errors

The dashboard proxies `/seldon/*` requests to the Seldon container. If the proxy fails:

```bash
# Verify Seldon is reachable from dashboard container
docker compose exec dashboard wget -qO- http://seldon:18789/health
```
