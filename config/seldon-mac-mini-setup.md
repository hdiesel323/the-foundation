# Seldon Orchestrator — Mac Mini Deployment

Seldon runs on the Mac Mini (100.64.0.1), separate from the VPS Docker Compose stack.

## Architecture

```
Mac Mini (100.64.0.1)        Hetzner VPS (100.64.0.2)
┌─────────────────────┐      ┌──────────────────────────┐
│ Seldon     :18789   │◄────►│ PostgreSQL    :5432       │
│ Rescue Bot :19001   │      │ daneel        :18790      │
│ Telegram Gateway    │      │ hardin        :18791      │
│                     │      │ magnifico     :18792      │
│                     │      │ trader        :18793      │
│                     │      │ gaal          :18794      │
│                     │      │ preem         :18797      │
│                     │      │ arkady        :18798      │
│                     │      │ Prometheus    :9090       │
│                     │      │ Grafana       :3000       │
│                     │      │ Loki          :3100       │
└─────────────────────┘      └──────────────────────────┘
        ▲                            ▲
        └────── Tailscale VPN ───────┘
```

## Prerequisites

1. Tailscale installed and connected (see `scripts/setup-tailscale.sh`)
2. Node.js 20+ installed
3. Seldon project built: `cd seldon && npm install`

## Running Seldon

Seldon listens on port 18789 on the Mac Mini (100.64.0.1).

```bash
cd seldon

# Set environment variables for VPS database access via Tailscale
export SELDON_PORT=18789
export DB_HOST=100.64.0.2    # VPS via Tailscale
export DB_PORT=5432
export DB_NAME=openclaw
export DB_USER=openclaw
export DB_PASSWORD=<your_db_password>

# Start Seldon
npx tsx index.ts
```

### Agent Connectivity

Seldon connects to all agents via Tailscale at 100.64.0.2:{port}:

| Agent | Tailscale Endpoint |
|-------|-------------------|
| daneel | 100.64.0.2:18790 |
| hardin | 100.64.0.2:18791 |
| magnifico | 100.64.0.2:18792 |
| trader | 100.64.0.2:18793 |
| gaal | 100.64.0.2:18794 |
| preem | 100.64.0.2:18797 |
| arkady | 100.64.0.2:18798 |

### Telegram Gateway

Seldon handles the Telegram gateway binding on Mac Mini. The Telegram bot webhook URL routes through Cloudflare Tunnel to the Mac Mini.

Configuration in `config/channels.json`:
- Telegram `webhookUrl` points to the Cloudflare Tunnel hostname
- Tunnel routes to Mac Mini's Seldon on port 18789
- Bot token stored in `secrets/telegram_token.txt`

## Rescue Bot

The rescue bot also runs on Mac Mini, on port 19001, as a systemd service (not Docker).

```bash
# Install rescue bot as systemd service
openclaw --profile rescue setup
openclaw --profile rescue config
openclaw --profile rescue gateway --port 19001
openclaw --profile rescue install  # Creates systemd unit

# Verify
systemctl status openclaw-rescue
curl -f http://localhost:19001/health
```

Rescue bot monitors Seldon health at `http://localhost:18789/health`. On 3 consecutive failures (90 seconds), it takes over Slack/#openclaw and Telegram bindings.

See `config/rescue-monitor.yml` and `config/rescue-bot-setup.md` for full configuration.

## Verification

```bash
# Seldon health
curl -f http://100.64.0.1:18789/health

# Agent connectivity (from Mac Mini)
curl -f http://100.64.0.2:18790/health  # daneel
curl -f http://100.64.0.2:18791/health  # hardin

# Rescue bot health
curl -f http://100.64.0.1:19001/health

# VPS database (from Mac Mini via Tailscale)
psql -h 100.64.0.2 -U openclaw -d openclaw -c "SELECT 1"
```
