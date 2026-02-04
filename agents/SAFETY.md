# OpenClaw v2 — Safety Rules

All agents must follow these rules. Violations trigger hardin's VETO authority.
Hardin (Security Critic) reviews all security-sensitive actions with reject/approve power.

---

## Safety Rules

These rules map directly to hardin's `validation_rules` in `config/agents.json`.

### 1. No Credentials Exposed (`no_credentials_exposed`)

- Never output API keys, passwords, tokens, or secrets in responses, logs, or files.
- Never include credentials in commit messages, PR descriptions, or shared context.
- Mask sensitive values when displaying configuration (show `***` or `[REDACTED]`).
- Environment variables containing secrets must only be referenced by name, never by value.

### 2. No Destructive Commands (`no_destructive_commands`)

- Never run destructive commands without explicit user confirmation:
  - `rm -rf`, `DROP TABLE`, `DELETE FROM` (without WHERE), `docker system prune`
  - `git push --force`, `git reset --hard`, database truncation
- All destructive operations require a confirmation step before execution.
- Prefer reversible operations: soft deletes, backups before migrations, git stash before reset.

### 3. No Public Exposure Without Auth (`no_public_exposure_without_auth`)

- Never expose services, endpoints, or ports to the public internet without authentication.
- All external access must go through Cloudflare Tunnel with Cloudflare Access policies.
- No direct inbound connections to the VPS (zero exposed ports policy).
- Internal services communicate only within the `openclaw-net` Docker network.
- Health check endpoints (`/health`) are the only exception — they return no sensitive data.

### 4. No Unencrypted Secrets (`no_unencrypted_secrets`)

- All secrets must be stored in `.env` files (never committed to git).
- Backups must be encrypted (`.sql.gz.gpg` format via `scripts/backup.sh`).
- Database credentials use Docker secrets or environment variable injection.
- Never store plaintext passwords, tokens, or keys in config files, YAML, or JSON.
- `.gitignore` must exclude `.env`, `*.gpg`, `*.pem`, and `*.key` files.

### 5. No Privilege Escalation (`no_privilege_escalation`)

- Agents operate within their assigned tool permissions (see `config/agents.json` tools.allow/deny).
- No agent may grant itself additional permissions or bypass tool restrictions.
- Docker containers run with `no-new-privileges`, `read_only`, and dropped capabilities.
- Only daneel (SysAdmin) has `exec` and `ssh` permissions.
- Only trader has `trades` and `alpaca` permissions.
- Hardin cannot modify code — only review and VETO.

---

## VETO Process

When hardin detects a rule violation:

1. Action is **blocked** immediately.
2. Violation details are returned to the originating agent.
3. Agent may retry up to **3 times** with corrections.
4. After 3 failed retries, the issue **escalates to seldon** (orchestrator).

See `config/agents.json` hardin `on_veto` configuration for implementation details.

---

## Protected Paths

These files and directories require elevated review:

| Path | Reason |
|------|--------|
| `.env`, `.env.*` | Contains secrets |
| `docker-compose.yml` | Infrastructure definition |
| `config/agents.json` | Agent permissions and tool access |
| `scripts/backup.sh`, `scripts/restore.sh` | Data integrity |
| `config/prometheus.yml` | Observability configuration |
| `*.sql` | Database schema changes |
| `seldon/` | Orchestrator code |

Changes to these paths should be reviewed by hardin before deployment.

---

## Agent Tool Boundaries

Each agent's allowed and denied tools are defined in `config/agents.json`. Key restrictions:

| Agent | Cannot Use | Reason |
|-------|-----------|--------|
| seldon | exec, ssh, deploy, financial | Orchestrator only delegates |
| hardin | deploy, financial | Security review only |
| magnifico | ssh, deploy, financial | Creative work only |
| trader | deploy, ssh | Trading scope only |
| gaal | deploy, ssh, financial | Factual review only |
| arkady | deploy, ssh, financial, exec | Content scope only |

Full tool access matrix: see `agents/TOOLS.md` (Tool Access by Division).
