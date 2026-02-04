# Contributing to The Foundation

Thank you for your interest in contributing to The Foundation, a production-grade multi-agent AI orchestration platform. This document provides guidelines for setting up your development environment and contributing to the project.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Code Style and Standards](#code-style-and-standards)
- [Security Requirements](#security-requirements)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Agent Development Guide](#agent-development-guide)
- [License](#license)

## Development Environment Setup

### Prerequisites

- Docker and Docker Compose
- Node.js 20+ and npm
- Git
- `jq` (for JSON processing)
- PostgreSQL client tools (optional, for local testing)

### Initial Setup

1. Clone the repository:
```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

2. Create the secrets directory structure:
```bash
mkdir -p secrets
chmod 700 secrets
```

3. Copy and configure secrets (see [Security Requirements](#security-requirements)):
```bash
# Required secrets
echo "your-db-password" > secrets/db_password.txt
echo "sk-ant-..." > secrets/anthropic_key.txt
echo "your-grafana-password" > secrets/grafana_password.txt
echo "your-backup-passphrase" > secrets/backup_passphrase.txt

# Optional secrets (for testing specific integrations)
echo "xoxb-..." > secrets/slack_bot_token.txt
echo "xapp-..." > secrets/slack_app_token.txt
echo "telegram-bot-token" > secrets/telegram_token.txt

# Lock down permissions
chmod 600 secrets/*.txt
```

4. Start the development stack:
```bash
docker compose up -d
```

5. Verify all services are healthy:
```bash
docker compose ps
docker compose logs --tail 20
```

6. Access the dashboard:
```bash
# Dashboard runs on port 18810
open http://localhost:18810
```

### Service Ports

| Service | Port | Purpose |
|---------|------|---------|
| Seldon Protocol API | 18789 | Multi-agent coordination |
| Dashboard | 18810 | Web interface |
| PostgreSQL | 5434 | Database (mapped from 5432) |
| Prometheus | 9090 | Metrics |
| Grafana | 3001 | Monitoring dashboards |
| Loki | 3100 | Log aggregation |
| Anthropic Router | 3333 | Claude API proxy |

## Project Structure

```
openclaw-002/
├── agents/              # Agent personality definitions (SOUL.md files)
├── config/              # Configuration files
│   ├── agents.json      # Agent definitions and model tiers
│   ├── prometheus.yml   # Prometheus configuration
│   └── grafana/         # Grafana dashboards and datasources
├── dashboard/           # Web dashboard (Node.js + vanilla JS)
├── docker-compose.yml   # Service orchestration
├── init-scripts/        # PostgreSQL initialization scripts
├── mcp-gateway/         # MCP server gateway
├── seldon/              # Seldon Protocol server implementation
├── scripts/             # Automation and maintenance scripts
└── secrets/             # Credentials (gitignored)
```

## Code Style and Standards

### TypeScript

- Use ESM modules (`import`/`export`, not `require`)
- Enable strict mode in `tsconfig.json`
- Use explicit types; avoid `any` unless absolutely necessary
- Follow functional programming patterns where appropriate
- Prefer `const` over `let`; avoid `var`

Example:
```typescript
// Good
export async function fetchAgentStatus(agentId: string): Promise<AgentStatus> {
  const response = await fetch(`/api/agents/${agentId}`);
  return response.json();
}

// Avoid
var getStatus = function(id) {
  return fetch('/api/agents/' + id).then(r => r.json());
}
```

### JavaScript

- Use modern ES2022+ features
- Prefer async/await over raw promises
- Use template literals for string interpolation
- Destructure objects and arrays where it improves readability

### Docker

- All Dockerfiles should use Alpine Linux base images where possible
- Pin specific version tags (e.g., `node:20-alpine`, not `node:latest`)
- Use multi-stage builds for production images
- Run containers as non-root users
- Enable health checks for all services

### SQL

- Use lowercase for SQL keywords in application code
- Use snake_case for table and column names
- Always use parameterized queries (no string concatenation)
- Include comments for complex queries

## Security Requirements

### Critical: Never Commit Secrets

All secrets MUST be stored in the `secrets/` directory, which is gitignored. Never commit:

- API keys
- Database passwords
- OAuth tokens
- Private keys
- Tunnel tokens
- Service credentials

### Secrets Management

The project uses Docker secrets for production and file-based secrets for development:

```bash
# Development: secrets/*.txt files
secrets/
├── db_password.txt
├── anthropic_key.txt
├── openai_key.txt
├── slack_bot_token.txt
├── slack_app_token.txt
├── telegram_token.txt
├── grafana_password.txt
└── backup_passphrase.txt
```

For production deployments, consider using:
- Docker Swarm secrets
- 1Password Service Accounts
- HashiCorp Vault
- Cloud provider secret managers (AWS Secrets Manager, GCP Secret Manager)

### Code Security

- Always validate user input
- Use prepared statements for database queries
- Never log sensitive information
- Follow principle of least privilege for agent permissions
- Review Dockerfiles for security best practices

## Testing

### Manual Testing

Before submitting a PR, verify:

1. All Docker services start and reach healthy state:
```bash
docker compose up -d
docker compose ps  # All should show "healthy"
```

2. Database schema is valid:
```bash
docker exec openclaw-postgres psql -U openclaw -d openclaw -c "\dt"
```

3. API endpoints respond:
```bash
curl -f http://localhost:18789/health
curl -f http://localhost:18810/health
```

4. No secrets in git:
```bash
git diff | grep -i "password\|secret\|token\|key" && echo "STOP: Secrets detected!"
```

### Automated Testing

When adding new features, include appropriate tests:

- Unit tests for business logic
- Integration tests for API endpoints
- Health checks for new services
- Database migration verification

## Pull Request Process

1. Fork the repository and create a feature branch:
```bash
git checkout -b feature/your-feature-name
```

2. Make your changes following the code style guidelines

3. Test your changes thoroughly:
```bash
docker compose down -v  # Clean slate
docker compose up -d
# Run your tests
```

4. Commit with clear, descriptive messages:
```bash
git commit -m "feat: add agent health monitoring endpoint"
```

Use conventional commit prefixes:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `chore:` for maintenance tasks
- `refactor:` for code refactoring
- `test:` for adding tests
- `security:` for security improvements

5. Push to your fork and submit a pull request:
```bash
git push origin feature/your-feature-name
```

6. In your PR description:
   - Explain what changed and why
   - Reference any related issues
   - Include screenshots for UI changes
   - List any breaking changes
   - Confirm you tested locally

### PR Review Criteria

Your PR will be reviewed for:
- Code quality and style compliance
- Security implications
- Test coverage
- Documentation updates
- Breaking changes properly communicated
- No secrets committed

## Issue Reporting

### Bug Reports

Include:
- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Docker version, Node version)
- Relevant logs (sanitized of secrets)
- Screenshots if applicable

### Feature Requests

Include:
- Use case and problem being solved
- Proposed solution
- Alternative approaches considered
- Impact on existing functionality

### Security Issues

Do NOT open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for reporting instructions.

## Agent Development Guide

The Foundation uses a multi-agent architecture with 14 specialized agents organized into divisions.

### Agent Structure

Each agent consists of:
- Entry in `config/agents.json` with port, role, division, and tools
- SOUL.md file in `agents/<agent-name>/SOUL.md` defining personality
- Optional workspace directory for agent-specific data

### Adding a New Agent

1. Define the agent in `config/agents.json`:
```json
{
  "instances": {
    "your_agent": {
      "port": 18803,
      "role": "Your Agent Role",
      "modelTier": "claude",
      "division": "operations",
      "location": "vps-1",
      "soulPath": "~/.openclaw/agents/your_agent/SOUL.md",
      "tools": {
        "allow": ["your", "allowed", "tools"],
        "deny": ["deploy", "ssh", "financial"]
      }
    }
  }
}
```

2. Create the agent directory and SOUL.md:
```bash
mkdir -p agents/your_agent
cat > agents/your_agent/SOUL.md << 'EOF'
# Your Agent Name

## Role
Brief description of the agent's purpose.

## Personality
- Trait 1
- Trait 2
- Trait 3

## Responsibilities
- Responsibility 1
- Responsibility 2

## Decision Framework
How the agent makes decisions and prioritizes work.
EOF
```

3. Add database table if needed (in `init-scripts/`):
```sql
CREATE TABLE your_agent_data (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  -- your columns
);
```

4. Test the agent:
```bash
docker compose restart seldon
docker compose logs -f seldon
```

### Agent Divisions

Agents are organized into four divisions:
- **Command**: Orchestration and coordination (seldon)
- **Infrastructure**: System administration and security (daneel, hardin)
- **Operations**: Creative, content, project management (magnifico, arkady, venabili)
- **Commerce**: Trading, revenue, sales, advertising (trader, mallow, riose, preem)
- **Intelligence**: Research, analysis, fact-checking (mis, amaryl, demerzel, gaal)

### Agent Authority Levels

Some agents have veto authority:
- **hardin** (Security Critic): Can veto security violations
- **gaal** (Factual Critic): Can veto factual inaccuracies

When adding veto authority:
```json
{
  "authority": {
    "level": "veto",
    "scope": "security|factual",
    "can_reject": true,
    "can_approve": true,
    "cannot_modify": true
  },
  "on_veto": {
    "return_to_originator": true,
    "max_retries": 3,
    "escalate_after_retries": "seldon"
  }
}
```

### Model Tier Assignment

All agents use the `claude` tier (Claude Sonnet 4.5) as primary. Some agents have overflow tiers for large contexts:
- **mis** and **demerzel**: Fall back to `grok_reasoning` or `grok_fast` for 2M context window
- All others: Use `claude` exclusively

## License

The Foundation is licensed under the Apache License 2.0. By contributing, you agree that your contributions will be licensed under the same license.

See [LICENSE](LICENSE) for the full license text.

## Questions?

- Open a discussion in GitHub Discussions
- Join our community channels (coming soon)
- Review existing issues and PRs

Thank you for contributing to The Foundation!
