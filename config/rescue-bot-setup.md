# Rescue Bot Setup

The rescue bot monitors the Main Gateway (port 18789) and takes over Slack/Telegram bindings if it fails. It runs as a **systemd service** on port **19001** — not as a Docker container. This ensures it can restart Docker services if needed.

## How It Works

1. Rescue bot runs as a systemd service on port 19001, checking 18789 health every 30s
2. After 3 consecutive failures (90s), it alerts via Slack, takes over channel bindings, and attempts to restart the main service
3. Once the main gateway recovers, rescue bot releases bindings and returns to monitoring
4. This is a lightweight monitor, not a full agent — it only handles channel routing during outages

## Prerequisites

- OpenClaw installed on the host (not just in Docker)
- `config/rescue-monitor.yml` configured (see below)
- Slack bot token and Telegram token available in secrets/

## Configuration

The rescue bot reads `config/rescue-monitor.yml`:

```yaml
monitor:
  target: http://localhost:18789/health
  interval: 30s
  timeout: 10s
  failureThreshold: 3    # 3 failures × 30s = 90s before takeover

  onFailure:
    - alert:
        channel: slack
        message: "ALERT: Main gateway down. Rescue bot taking over."
    - takeover:
        bindings: ["slack:#openclaw"]
    - attempt_recovery:
        command: "systemctl restart openclaw-main"
        maxAttempts: 3
```

## Emergency Bindings

The rescue bot takes over channel bindings when the main gateway is down:

| Priority | Channel | Target | Purpose |
|----------|---------|--------|---------|
| Primary | Slack | #openclaw | Main user interface — rescue bot claims this first |
| Fallback | Telegram | Admin chat ID | Mobile/fallback when Slack is unavailable |

Configure emergency bindings:

```bash
openclaw --profile rescue config set bindings '[
  {"channel": "slack", "channelId": "#openclaw"},
  {"channel": "telegram", "chatId": "${TELEGRAM_ADMIN_CHAT_ID}"}
]'
```

## Installation

### 1. Create the openclaw service user (if not already present)

```bash
sudo useradd -r -s /usr/sbin/nologin openclaw
sudo mkdir -p /opt/openclaw/logs
sudo chown -R openclaw:openclaw /opt/openclaw
```

### 2. Copy the systemd unit file

```bash
sudo cp config/rescue-bot.service /etc/systemd/system/openclaw-rescue.service
sudo chmod 644 /etc/systemd/system/openclaw-rescue.service
```

### 3. Reload systemd and enable the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw-rescue
```

This ensures the rescue monitor:
- Starts automatically on boot (`WantedBy=multi-user.target`)
- Restarts on failure (`Restart=always`, 10s delay)
- Runs independently of Docker

### 4. Start the service

```bash
sudo systemctl start openclaw-rescue
```

### 5. Verify the service

```bash
# Check systemd service status
sudo systemctl status openclaw-rescue

# Watch live logs
sudo journalctl -u openclaw-rescue -f

# Check recent logs (last 50 lines)
sudo journalctl -u openclaw-rescue -n 50 --no-pager
```

### Stopping / Restarting

```bash
sudo systemctl stop openclaw-rescue
sudo systemctl restart openclaw-rescue
```

### Uninstalling

```bash
sudo systemctl stop openclaw-rescue
sudo systemctl disable openclaw-rescue
sudo rm /etc/systemd/system/openclaw-rescue.service
sudo systemctl daemon-reload
```

## Port Mapping

| Service | Port | Purpose |
|---------|------|---------|
| Main Gateway | 18789 | Primary user-facing service (Seldon, Slack Socket Mode) |
| Rescue Gateway | 19001 | Dormant failover — activates only when 18789 is unresponsive |

The rescue gateway on port 19001 is **dormant** by default. It activates only if port 18789 is unresponsive for 3 consecutive health checks (90 seconds).

## Key Design Decision: systemd, Not Docker

The rescue bot runs as a **separate systemd service**, not a Docker container, because:

1. It needs to restart Docker services (`systemctl restart openclaw-main`) — a container cannot reliably restart its own orchestrator
2. It must survive Docker daemon failures
3. It operates independently of the Docker Compose stack it monitors

## Failover Sequence

```
Normal Operation:
  Main Gateway (18789) ← Slack #openclaw, Telegram
  Rescue Bot (19001)   ← monitoring 18789 every 30s

After 3 failures (90s):
  Main Gateway (18789) ← DOWN
  Rescue Bot (19001)   ← alerts Slack, takes over #openclaw + Telegram
                       ← attempts systemctl restart (up to 3 times)

After Recovery:
  Main Gateway (18789) ← recovers, reclaims bindings
  Rescue Bot (19001)   ← releases bindings, returns to monitoring
```
