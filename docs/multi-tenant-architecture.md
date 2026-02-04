# Foundation Cloud: Multi-Tenant Architecture

**Version:** 1.0  
**Last Updated:** February 3, 2026  
**Status:** Design Phase  

## Executive Summary

This document defines the architecture for Foundation Cloud, a hosted multi-tenant version of The Foundation AI orchestration platform. The design prioritizes pragmatic implementation over theoretical perfection, focusing on a phased rollout that can evolve from the current single-tenant Docker Compose stack.

**Key Decisions:**
- **Isolation Model:** Hybrid approach (Option C) — shared PostgreSQL with row-level security, isolated Seldon instances per tenant
- **Infrastructure:** Kubernetes on Hetzner Cloud for cost efficiency
- **Tenant Routing:** Subdomain-based routing with JWT authentication
- **Database Strategy:** Schema-per-tenant with centralized auth database
- **Billing:** Stripe-based metering on tasks dispatched and agent-hours

**Target Launch:** 60 days (MVP Starter tier), 90 days (Pro tier with full feature set)

---

## Table of Contents

1. [Context and Requirements](#1-context-and-requirements)
2. [Isolation Model](#2-isolation-model)
3. [Database Architecture](#3-database-architecture)
4. [API and Tenant Routing](#4-api-and-tenant-routing)
5. [Agent Provisioning](#5-agent-provisioning)
6. [Discord Integration](#6-discord-integration)
7. [Billing and Usage Metering](#7-billing-and-usage-metering)
8. [Infrastructure](#8-infrastructure)
9. [Security Model](#9-security-model)
10. [Migration Path](#10-migration-path)
11. [Phase Plan](#11-phase-plan)
12. [Cost Analysis](#12-cost-analysis)

---

## 1. Context and Requirements

### 1.1 Current Architecture

The Foundation self-hosted runs as a monolithic Docker Compose stack:
- 14 AI agents coordinated by Seldon Protocol (Express.js/TypeScript)
- Single PostgreSQL database (openclaw schema)
- Docker-based service orchestration
- Discord integration via bot token
- Dashboard web UI on port 18810
- All services on shared `openclaw-net` Docker network

### 1.2 Cloud Service Tiers

| Tier | Agents | Workflows | Tasks/Month | Price | Target Customer |
|------|--------|-----------|-------------|-------|----------------|
| **Starter** | 5 agents | 5 templates | 500 | $49/mo | Solopreneurs, small teams |
| **Pro** | 14 agents | Unlimited | 5,000 | $149/mo | Growing businesses |
| **Enterprise** | Custom | Custom | Unlimited | Custom | Large orgs, custom workflows |

### 1.3 Multi-Tenant Requirements

**Functional:**
- Tenant isolation (data, agents, API keys)
- Per-tenant Discord server integration
- Custom agent configuration
- Usage metering for billing
- Self-service onboarding
- Tier enforcement (agent limits, workflow limits)

**Non-Functional:**
- 99.5% uptime SLA (Starter/Pro), 99.9% (Enterprise)
- Sub-2s task dispatch latency
- Support 100 concurrent tenants (launch target)
- Cost-efficient at scale ($30-50 COGS per tenant/month on Pro tier)

---

## 2. Isolation Model

### 2.1 Decision: Hybrid Approach (Option C)

**Selected:** Shared PostgreSQL cluster with schema-per-tenant + isolated Seldon instances per tenant

**Rationale:**

| Aspect | One Stack Per Tenant (A) | Shared Everything (B) | Hybrid (C) |
|--------|---------------------------|------------------------|------------|
| **Isolation** | Perfect | Weak | Strong |
| **Cost** | $40-60/tenant/month | $5-10/tenant/month | $15-25/tenant/month |
| **Complexity** | Low (just replicate) | High (tenant context everywhere) | Medium |
| **Scaling** | Linear cost growth | Efficient | Balanced |
| **Blast Radius** | Zero | High (one bug affects all) | Low (DB shared, apps isolated) |

**Why Hybrid Wins:**
- Strong isolation where it matters (agent execution, API keys, Discord tokens)
- Cost-efficient database sharing (PostgreSQL handles 1000s of schemas easily)
- Easier to debug than shared app layer (tenant context bugs)
- Supports tiered offerings (Starter gets shared node pool, Enterprise gets dedicated)

### 2.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Ingress Layer                          │
│  (Traefik / Nginx) — Subdomain Routing + JWT Auth          │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼─────────┐  ┌──────▼──────────┐  ┌────▼──────────┐
│  tenant-acme    │  │  tenant-beta    │  │  tenant-zeta  │
│  Seldon Pod     │  │  Seldon Pod     │  │  Seldon Pod   │
│  (14 agents)    │  │  (14 agents)    │  │  (14 agents)  │
│  Dashboard      │  │  Dashboard      │  │  Dashboard    │
└───────┬─────────┘  └──────┬──────────┘  └────┬──────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
        ┌───────────────────▼───────────────────┐
        │      Shared PostgreSQL Cluster        │
        │  (schema: acme, beta, zeta, + auth)   │
        └───────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼─────────┐  ┌──────▼──────────┐  ┌────▼──────────┐
│  Anthropic API  │  │  Discord API    │  │  Stripe API   │
│  (per-tenant    │  │  (tenant bot)   │  │  (billing)    │
│   API key)      │  │                 │  │               │
└─────────────────┘  └─────────────────┘  └───────────────┘
```

### 2.3 What Gets Isolated

| Resource | Isolation Method |
|----------|------------------|
| **Seldon Protocol instance** | Dedicated Kubernetes pod per tenant |
| **Dashboard** | Sidecar container in Seldon pod |
| **Database schema** | PostgreSQL schema-per-tenant (RLS policies) |
| **Anthropic API keys** | Per-tenant k8s secrets (tenant-managed or pooled) |
| **Discord bot token** | Per-tenant k8s secrets (OAuth2 flow during onboarding) |
| **Agent configuration** | Tenant-specific `agents.json` in ConfigMap |
| **Workflow templates** | Tenant-specific `workflows.json` in ConfigMap |

### 2.4 What Gets Shared

| Resource | Rationale |
|----------|-----------|
| **PostgreSQL cluster** | Cost-efficient, schema isolation is strong |
| **Prometheus + Grafana** | Central observability with tenant labels |
| **Kubernetes control plane** | Standard multi-tenancy model |
| **Ingress controller** | Routes by subdomain, enforces auth |
| **anthropic-router** | Optional shared Max subscription pool (if we provide API) |

---

## 3. Database Architecture

### 3.1 Schema-Per-Tenant Model

**Structure:**
```
PostgreSQL Cluster
├── auth_db (shared)
│   ├── tenants (id, slug, tier, stripe_customer_id, created_at, status)
│   ├── users (id, tenant_id, email, password_hash, role, created_at)
│   ├── api_keys (id, tenant_id, key_hash, scopes, last_used_at)
│   ├── usage_events (id, tenant_id, event_type, count, timestamp)
│   └── billing_invoices (id, tenant_id, stripe_invoice_id, amount, period)
│
├── tenant_acme (isolated schema)
│   ├── tasks
│   ├── agents
│   ├── messages
│   ├── conversations
│   ├── discord_thread_messages
│   ├── preferences
│   └── workflows
│
├── tenant_beta (isolated schema)
│   └── (same tables as above)
│
└── tenant_zeta (isolated schema)
    └── (same tables as above)
```

### 3.2 Schema Provisioning Flow

```typescript
// When new tenant signs up:
async function provisionTenant(tenantSlug: string, tier: string) {
  // 1. Create tenant record in auth_db
  const tenant = await db.auth.tenants.create({
    slug: tenantSlug,
    tier: tier,
    status: 'provisioning'
  });

  // 2. Create isolated schema
  await db.raw(`CREATE SCHEMA IF NOT EXISTS tenant_${tenantSlug}`);

  // 3. Run migration scripts on new schema
  await runMigrations(`tenant_${tenantSlug}`, [
    '01-schema.sql',
    '02-business-schema.sql',
    '03-discord-threads.sql'
  ]);

  // 4. Create tenant-specific database user with RLS policies
  await db.raw(`
    CREATE USER ${tenantSlug}_app WITH PASSWORD '${generateSecurePassword()}';
    GRANT USAGE ON SCHEMA tenant_${tenantSlug} TO ${tenantSlug}_app;
    GRANT ALL ON ALL TABLES IN SCHEMA tenant_${tenantSlug} TO ${tenantSlug}_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA tenant_${tenantSlug} 
      GRANT ALL ON TABLES TO ${tenantSlug}_app;
  `);

  // 5. Seed default agent configuration
  await seedAgentConfig(tenant.id, tier);

  // 6. Deploy Seldon pod
  await k8s.deployTenantPod(tenantSlug, {
    dbSchema: `tenant_${tenantSlug}`,
    dbUser: `${tenantSlug}_app`,
    tier: tier
  });

  // 7. Update tenant status
  await db.auth.tenants.update(tenant.id, { status: 'active' });
}
```

### 3.3 Row-Level Security (Defense in Depth)

Even with schema isolation, add RLS policies for paranoid security:

```sql
-- Example: Only allow tenant's API key to read their tasks
ALTER TABLE tenant_acme.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_acme.tasks
  USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Set tenant context at connection time
SET app.current_tenant = 'acme-uuid-here';
```

### 3.4 Migration Strategy

**Initial Setup:**
- Run migrations on `auth_db` once (shared schema)
- Provision tenant schema on signup

**Schema Updates:**
- Maintain version tracking in `auth_db.schema_versions` table
- Run migrations across all tenant schemas in parallel (k8s Job)
- Zero-downtime: Use Postgres transactional DDL

```bash
# Migration script (runs as k8s CronJob)
for schema in $(psql -t -c "SELECT 'tenant_' || slug FROM auth_db.tenants WHERE status='active'"); do
  psql -c "SET search_path TO $schema; \i migrations/004-add-column.sql"
done
```

### 3.5 Database Connection Pooling

**Problem:** Each Seldon pod needs DB connection pool → 100 tenants × 10 connections = 1000 connections

**Solution:** Use PgBouncer in transaction mode

```
┌─────────────┐
│ Seldon Pod  │ ──┐
└─────────────┘   │
┌─────────────┐   ├──► ┌───────────┐     ┌────────────┐
│ Seldon Pod  │ ──┤    │ PgBouncer │ ───► │ PostgreSQL │
└─────────────┘   │    │ (200 conn)│     │ (50 conn)  │
┌─────────────┐   │    └───────────┘     └────────────┘
│ Seldon Pod  │ ──┘
└─────────────┘
```

**Configuration:**
- PgBouncer pool size: 200 connections
- PostgreSQL max_connections: 500
- Per-tenant Seldon pool: 5 connections

---

## 4. API and Tenant Routing

### 4.1 Subdomain-Based Routing

**Format:** `https://{tenant-slug}.foundationcloud.dev`

**Example:**
- Acme Corp → `https://acme.foundationcloud.dev`
- Beta Inc → `https://beta.foundationcloud.dev`
- Dashboard → `https://acme.foundationcloud.dev/dashboard`
- API → `https://acme.foundationcloud.dev/api/seldon/tasks`

**Why subdomains:**
- Clean tenant isolation (no path prefix ugliness)
- Separate cookies/localStorage per tenant (security)
- Easier CORS handling
- Matches SaaS best practices (Slack, Notion, GitHub)

### 4.2 Ingress Routing (Traefik)

```yaml
# Traefik IngressRoute per tenant
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: tenant-acme
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`acme.foundationcloud.dev`)
      kind: Rule
      services:
        - name: seldon-acme
          port: 18789
      middlewares:
        - name: auth-jwt
        - name: rate-limit-acme
  tls:
    secretName: foundation-wildcard-tls
```

### 4.3 Authentication Flow

**JWT-Based Auth:**

```typescript
// Login flow
POST /auth/login
{
  "email": "admin@acme.com",
  "password": "..."
}

Response:
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tenant_slug": "acme",
  "user": { "id": "...", "role": "admin" }
}

// JWT payload
{
  "sub": "user-uuid",
  "tenant_id": "tenant-uuid",
  "tenant_slug": "acme",
  "role": "admin",
  "tier": "pro",
  "exp": 1735689600
}
```

**Middleware:**

```typescript
// JWT verification middleware (runs on every API request)
async function verifyJWT(req: Request, res: Response, next: Function) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'No token' });

  const decoded = jwt.verify(token, process.env.JWT_SECRET);
  
  // Verify tenant slug in URL matches JWT claim
  const requestedTenant = req.hostname.split('.')[0]; // "acme" from acme.foundationcloud.dev
  if (decoded.tenant_slug !== requestedTenant) {
    return res.status(403).json({ error: 'Tenant mismatch' });
  }

  // Attach tenant context to request
  req.tenant = decoded;
  req.dbSchema = `tenant_${decoded.tenant_slug}`;
  
  next();
}
```

### 4.4 API Key Authentication (Programmatic Access)

For CI/CD and external integrations:

```bash
# Create API key
POST /api/keys
Authorization: Bearer {jwt-token}
{
  "name": "CI Pipeline",
  "scopes": ["tasks:write", "workflows:read"]
}

Response:
{
  "key": "oc_live_acme_a3f8d9e2...",  # Only shown once
  "id": "key-uuid",
  "scopes": ["tasks:write", "workflows:read"]
}

# Use API key
curl https://acme.foundationcloud.dev/api/seldon/tasks \
  -H "Authorization: Bearer fc_live_acme_a3f8d9e2..."
```

**API Key Format:**
- Prefix: `fc_live_` (production) or `fc_test_` (sandbox)
- Tenant slug: `acme`
- Random suffix: 32 hex chars
- Stored as bcrypt hash in `auth_db.api_keys`

### 4.5 Rate Limiting

**Per-Tenant Quotas:**

| Tier | API Requests/Min | Tasks/Hour | Concurrent Tasks |
|------|------------------|------------|------------------|
| Starter | 60 | 20 | 3 |
| Pro | 300 | 200 | 10 |
| Enterprise | Custom | Unlimited | 50 |

**Implementation:**
- Redis-backed rate limiter (token bucket algorithm)
- Key: `rate_limit:{tenant_id}:{endpoint}`
- Middleware checks before routing to tenant pod

```typescript
// Rate limit middleware
async function rateLimitMiddleware(req, res, next) {
  const key = `rate_limit:${req.tenant.id}:api`;
  const limit = TIER_LIMITS[req.tenant.tier].requests_per_minute;
  
  const current = await redis.incr(key);
  if (current === 1) {
    await redis.expire(key, 60);
  }
  
  if (current > limit) {
    return res.status(429).json({
      error: 'Rate limit exceeded',
      limit: limit,
      reset_at: await redis.ttl(key)
    });
  }
  
  next();
}
```

---

## 5. Agent Provisioning

### 5.1 Agent Configuration per Tier

**Starter Tier (5 agents):**
- Seldon (orchestrator)
- Daneel (builder)
- Magnifico (creative)
- Gaal (research)
- Venabili (project management)

**Pro Tier (14 agents):**
- All agents from `config/agents.json`

**Enterprise Tier:**
- Custom agent selection
- Custom tool access
- Custom model routing (bring your own API keys)

### 5.2 Provisioning Flow

When a tenant signs up or upgrades:

```typescript
async function provisionAgents(tenantSlug: string, tier: string) {
  const agentConfig = await loadAgentTemplate(tier);
  
  // 1. Create ConfigMap with tenant-specific agent config
  const configMap = {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: `agents-config-${tenantSlug}`,
      namespace: 'openclaw'
    },
    data: {
      'agents.json': JSON.stringify(agentConfig),
      'workflows.json': JSON.stringify(await loadWorkflowTemplate(tier))
    }
  };
  await k8s.createConfigMap(configMap);

  // 2. Create Secret with tenant API keys
  const secret = {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: {
      name: `tenant-secrets-${tenantSlug}`,
      namespace: 'openclaw'
    },
    stringData: {
      discord_token: tenantData.discord_bot_token,
      anthropic_key: tenantData.anthropic_api_key || SHARED_ANTHROPIC_KEY,
      db_password: tenantData.db_password
    }
  };
  await k8s.createSecret(secret);

  // 3. Deploy Seldon pod with mounted config
  const deployment = {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: `seldon-${tenantSlug}`,
      namespace: 'openclaw',
      labels: { tenant: tenantSlug, tier: tier }
    },
    spec: {
      replicas: 1,
      selector: { matchLabels: { app: 'seldon', tenant: tenantSlug } },
      template: {
        metadata: { labels: { app: 'seldon', tenant: tenantSlug } },
        spec: {
          containers: [
            {
              name: 'seldon',
              image: 'ghcr.io/openclaw/seldon:v2.0',
              env: [
                { name: 'DB_SCHEMA', value: `tenant_${tenantSlug}` },
                { name: 'TENANT_SLUG', value: tenantSlug },
                { name: 'TIER', value: tier }
              ],
              envFrom: [
                { secretRef: { name: `tenant-secrets-${tenantSlug}` } }
              ],
              volumeMounts: [
                { name: 'config', mountPath: '/app/config' }
              ],
              resources: TIER_RESOURCES[tier]
            }
          ],
          volumes: [
            { name: 'config', configMap: { name: `agents-config-${tenantSlug}` } }
          ]
        }
      }
    }
  };
  await k8s.createDeployment(deployment);
}
```

### 5.3 API Key Management

**Two Models:**

**Option A: Tenant Brings Own Key (BYOK)**
- Tenant provides Anthropic API key during onboarding
- Stored encrypted in tenant secrets
- Tenant pays Anthropic directly (usage-based)
- OpenClaw Cloud fee is flat subscription + platform margin

**Option B: The Foundation Provides API (Pooled)**
- The Foundation manages shared Anthropic Max subscription ($100/mo flat-rate)
- Or bulk pay-as-you-go with volume discount
- Simpler onboarding (no API key required)
- The Foundation fee includes AI usage + platform margin

**Recommendation:** Hybrid approach
- Starter tier: Pooled API (simpler onboarding, lower barrier)
- Pro tier: BYOK option (power users want control/direct billing)
- Enterprise tier: Always BYOK (compliance, audit trail)

**Cost Math (Pooled Model):**
- Anthropic Max: $100/mo unlimited (via anthropic-router)
- Support ~20 Starter tenants per Max subscription
- Each Starter tenant: $49/mo → $980/mo revenue
- Anthropic cost: $100/mo → $880/mo gross margin (90%)
- Platform costs: ~$300/mo (infrastructure) → $580/mo net margin (59%)

### 5.4 Agent Customization (Enterprise)

Enterprise customers can customize:
- Agent selection (disable/enable specific agents)
- Tool access (grant/deny specific tools)
- Model routing (use GPT-4 for specific agents)
- Custom agents (bring your own agent definition)

Stored in tenant-specific ConfigMap, validated on deployment:

```typescript
// Enterprise custom agent validation
function validateCustomAgent(agent: AgentConfig, tier: string) {
  if (tier !== 'enterprise') {
    throw new Error('Custom agents only available on Enterprise tier');
  }
  
  // Validate required fields
  if (!agent.role || !agent.soulPath) {
    throw new Error('Agent must have role and soulPath');
  }
  
  // Validate tool access (security)
  const dangerousTools = ['exec', 'ssh', 'deploy'];
  if (agent.tools?.allow?.some(t => dangerousTools.includes(t))) {
    throw new Error('Dangerous tools require security review');
  }
  
  return true;
}
```

---

## 6. Discord Integration

### 6.1 Multi-Tenant Discord Architecture

**Problem:** Self-hosted OpenClaw uses a single Discord bot token. Multi-tenant needs each tenant to connect their own Discord server.

**Solution:** OAuth2 bot installation flow

### 6.2 Onboarding Flow

```
1. Tenant signs up on foundationcloud.dev
2. During setup wizard, clicks "Connect Discord"
3. Redirect to Discord OAuth2 authorize URL:
   https://discord.com/api/oauth2/authorize
     ?client_id={FOUNDATION_CLIENT_ID}
     &permissions={BOT_PERMISSIONS}
     &scope=bot+applications.commands
     &redirect_uri=https://app.foundationcloud.dev/discord/callback
     &state={TENANT_ID_ENCRYPTED}

4. User authorizes bot in their Discord server

5. Discord redirects back with auth code:
   https://app.foundationcloud.dev/discord/callback?code={AUTH_CODE}&state={TENANT_ID}

6. The Foundation exchanges code for bot token:
   POST https://discord.com/api/oauth2/token
   {
     "grant_type": "authorization_code",
     "code": "{AUTH_CODE}",
     "redirect_uri": "https://app.foundationcloud.dev/discord/callback"
   }
   
   Response: { "access_token": "...", "guild": { "id": "..." } }

7. Store bot token and guild_id in tenant secrets
8. Update tenant ConfigMap with Discord config
9. Restart Seldon pod to pick up new Discord connection
```

### 6.3 Discord Bot Deployment

**Single Bot Application, Multi-Tenant Mode:**

The Foundation maintains one Discord application (client_id), but each tenant gets a unique bot token after OAuth2 install.

**Why this works:**
- Discord bot tokens are per-installation (per guild)
- Each tenant's Seldon pod uses their own bot token
- Bot only has access to guilds where it was explicitly installed

**Bot Permissions Required:**
- Send Messages
- Send Messages in Threads
- Create Public Threads
- Manage Threads
- Read Message History
- Embed Links
- Attach Files

### 6.4 Thread Management per Tenant

Each tenant's Seldon pod manages threads in their own Discord server:

```typescript
// When task is created
async function createTaskThread(task: Task, tenant: Tenant) {
  const discordClient = new DiscordClient(tenant.discord_bot_token);
  
  // Create thread in tenant's configured channel
  const thread = await discordClient.channels.threads.create(tenant.discord_channel_id, {
    name: `[${task.id.slice(0, 8)}] ${task.name}`,
    type: ChannelType.PublicThread,
    autoArchiveDuration: 1440 // 24 hours
  });
  
  // Link thread to task in database
  await db.tasks.update(task.id, {
    discord_thread_id: thread.id,
    discord_channel_id: tenant.discord_channel_id
  });
  
  // Post initial message
  await thread.send({
    embeds: [{
      title: task.name,
      description: task.description,
      fields: [
        { name: 'Priority', value: task.priority, inline: true },
        { name: 'Lead Agent', value: task.lead_agent, inline: true },
        { name: 'Status', value: 'In Progress', inline: true }
      ],
      color: 0x00ff00
    }]
  });
}
```

### 6.5 Discord Rate Limits

Discord enforces per-bot rate limits:
- 50 requests per second (global)
- 5 requests per second (per channel)

**Multi-Tenant Implications:**
- Each tenant has separate bot token → separate rate limit bucket
- No contention between tenants
- Central rate limit tracking not needed

---

## 7. Billing and Usage Metering

### 7.1 Stripe Integration

**Setup:**
1. Create Stripe Products for each tier
2. Create Stripe Prices (monthly subscription)
3. Attach metered billing component for overages

**Stripe Product Structure:**

```typescript
const products = {
  starter: {
    id: 'prod_starter',
    name: 'Foundation Starter',
    price: 4900, // $49.00
    interval: 'month',
    features: {
      agents: 5,
      workflows: 5,
      tasks_included: 500
    },
    metered_components: [
      { name: 'extra_tasks', price_per_100: 500 } // $5 per 100 tasks over 500
    ]
  },
  pro: {
    id: 'prod_pro',
    name: 'Foundation Pro',
    price: 14900, // $149.00
    interval: 'month',
    features: {
      agents: 14,
      workflows: 'unlimited',
      tasks_included: 5000
    },
    metered_components: [
      { name: 'extra_tasks', price_per_1000: 2000 } // $20 per 1000 tasks over 5000
    ]
  }
};
```

### 7.2 Usage Events

**What to Meter:**

| Event Type | Billable | Frequency | Example |
|------------|----------|-----------|---------|
| `task.dispatched` | Yes | Per task | Task sent to agent |
| `workflow.started` | Yes (Pro+) | Per workflow | Workflow instantiated |
| `agent.hours` | No (flat tier) | Per hour | Agent active time |
| `api.request` | No (rate limited) | Per request | API call |
| `storage.bytes` | Future | Per GB/mo | Database size |

**Event Recording:**

```typescript
async function recordUsageEvent(tenantId: string, eventType: string, quantity: number = 1) {
  // 1. Record in local database (auth_db)
  await db.usage_events.create({
    tenant_id: tenantId,
    event_type: eventType,
    quantity: quantity,
    timestamp: new Date()
  });

  // 2. Send to Stripe (for metered billing)
  const tenant = await db.tenants.findById(tenantId);
  if (tenant.stripe_subscription_id) {
    await stripe.subscriptionItems.createUsageRecord(
      tenant.stripe_metered_item_id,
      {
        quantity: quantity,
        timestamp: Math.floor(Date.now() / 1000),
        action: 'increment'
      }
    );
  }
}

// Example: When task dispatched
await recordUsageEvent(tenant.id, 'task.dispatched', 1);
```

### 7.3 Tier Enforcement

**Enforcement Points:**

```typescript
// Middleware: Check tier limits before dispatching task
async function enforceTierLimits(req: Request, res: Response, next: Function) {
  const tenant = req.tenant;
  const tier = TIER_LIMITS[tenant.tier];
  
  // Check monthly task quota
  const currentMonth = new Date().toISOString().slice(0, 7); // "2026-02"
  const usage = await db.usage_events.aggregate({
    tenant_id: tenant.id,
    event_type: 'task.dispatched',
    timestamp: { $gte: `${currentMonth}-01` }
  });
  
  if (usage.total >= tier.tasks_per_month && tier.tasks_per_month !== Infinity) {
    return res.status(403).json({
      error: 'Task quota exceeded',
      usage: usage.total,
      limit: tier.tasks_per_month,
      upgrade_url: 'https://app.foundationcloud.dev/billing/upgrade'
    });
  }
  
  // Check concurrent task limit
  const activeTasks = await db.tasks.count({
    tenant_id: tenant.id,
    status: { $in: ['pending', 'in_progress'] }
  });
  
  if (activeTasks >= tier.concurrent_tasks) {
    return res.status(429).json({
      error: 'Concurrent task limit reached',
      active: activeTasks,
      limit: tier.concurrent_tasks
    });
  }
  
  next();
}
```

### 7.4 Billing Cycle

**Monthly Subscription:**
1. Stripe charges subscription fee on billing date (e.g., 1st of month)
2. Metered usage tracked throughout month
3. At end of month, Stripe invoices overage charges
4. If payment fails, tenant moves to `suspended` status (grace period: 7 days)
5. After grace period, tenant moves to `inactive` (services stopped)

**Usage Dashboard:**

Tenants can view usage in real-time:

```
GET /api/billing/usage?month=2026-02

Response:
{
  "month": "2026-02",
  "tier": "starter",
  "usage": {
    "tasks_dispatched": 387,
    "workflows_started": 12,
    "storage_mb": 145
  },
  "limits": {
    "tasks_included": 500,
    "tasks_remaining": 113,
    "overage_rate": "$5 per 100 tasks"
  },
  "projected_bill": {
    "subscription": 49.00,
    "overages": 0.00,
    "total": 49.00
  }
}
```

---

## 8. Infrastructure

### 8.1 Platform Choice: Kubernetes on Hetzner

**Why Kubernetes:**
- Industry standard for multi-tenant SaaS
- Native resource isolation (namespaces, resource quotas)
- Horizontal autoscaling (HPA)
- Rolling updates with zero downtime
- Rich ecosystem (Traefik, cert-manager, monitoring)

**Why Hetzner:**
- Cost: 60-70% cheaper than AWS/GCP for equivalent compute
- Performance: Dedicated vCPUs (not shared like AWS t3)
- European data residency (GDPR compliance)
- Good network (1Gbps ports, 20TB transfer included)

**Cost Comparison (100 tenants):**

| Resource | Hetzner | AWS | Savings |
|----------|---------|-----|---------|
| 4x CPX51 (16vCPU, 32GB) | €180/mo | $640/mo | -72% |
| PostgreSQL (CPX31: 8vCPU, 16GB) | €45/mo | $320/mo (RDS) | -86% |
| Load Balancer | €5/mo | $16/mo | -69% |
| **Total** | **€230/mo** | **$976/mo** | **-76%** |

### 8.2 Cluster Architecture

**Node Pools:**

```
┌─────────────────────────────────────────────────────────┐
│              Hetzner Kubernetes Cluster                 │
├─────────────────────────────────────────────────────────┤
│  Control Plane (Managed by Hetzner, free)              │
├─────────────────────────────────────────────────────────┤
│  Node Pool: Shared (Starter/Pro tenants)               │
│  ├─ 3x CPX51 (16 vCPU, 32GB RAM, €60/mo each)          │
│  ├─ Taints: tier=shared:NoSchedule                     │
│  └─ Capacity: ~60 tenant pods (avg 0.5 vCPU, 1GB each) │
├─────────────────────────────────────────────────────────┤
│  Node Pool: Enterprise (dedicated)                      │
│  ├─ 1x CPX51 per enterprise tenant                     │
│  ├─ Taints: tenant={slug}:NoSchedule                   │
│  └─ Full isolation, no noisy neighbors                 │
├─────────────────────────────────────────────────────────┤
│  Node Pool: Database                                    │
│  ├─ 1x CPX31 (8 vCPU, 16GB RAM, €45/mo)                │
│  ├─ Taints: workload=database:NoSchedule               │
│  └─ Runs: PostgreSQL primary + PgBouncer               │
├─────────────────────────────────────────────────────────┤
│  Node Pool: Infra                                       │
│  ├─ 1x CPX21 (4 vCPU, 8GB RAM, €20/mo)                 │
│  └─ Runs: Traefik, Prometheus, Grafana, Loki           │
└─────────────────────────────────────────────────────────┘
```

### 8.3 Resource Allocation per Tenant

**Starter Tier:**
```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

**Pro Tier:**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Enterprise Tier:**
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 8000m
    memory: 16Gi
```

### 8.4 Autoscaling

**Horizontal Pod Autoscaler (per tenant):**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: seldon-acme-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: seldon-acme
  minReplicas: 1
  maxReplicas: 5  # Pro tier, Starter limited to 1
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Pods
      pods:
        metric:
          name: active_tasks
        target:
          type: AverageValue
          averageValue: "10"
```

**Cluster Autoscaler:**
- Automatically add nodes when pod scheduling fails (insufficient capacity)
- Remove nodes when utilization < 50% for 10 minutes

### 8.5 PostgreSQL High Availability

**Setup:**
- Primary: Runs on dedicated database node
- Replica: Runs on second database node (async replication)
- PgBouncer: Connection pooling layer (runs on each app node)

**Failover:**
- Use Patroni (HA Postgres cluster manager)
- Automatic failover in <30 seconds
- Helm chart: `helm install postgres bitnami/postgresql-ha`

### 8.6 Backup Strategy

**Database Backups:**
- Automated daily snapshots via Hetzner Backups (€0.20/day)
- Point-in-time recovery via WAL archiving to S3-compatible storage (Hetzner Object Storage)
- Retention: 30 days daily, 12 months monthly

**Application State:**
- Tenant ConfigMaps/Secrets backed up to git repo (encrypted)
- Infrastructure as Code (Terraform) for full cluster rebuild

### 8.7 Monitoring

**Prometheus + Grafana Stack:**
- Prometheus scrapes metrics from all tenant pods
- Tenant label attached to all metrics
- Grafana dashboards with per-tenant filtering

**Key Metrics:**

| Metric | Type | Alert Threshold |
|--------|------|-----------------|
| `seldon_tasks_active{tenant}` | Gauge | > 90% of limit |
| `seldon_task_duration_seconds` | Histogram | p95 > 30s |
| `seldon_api_requests_total{tenant}` | Counter | Rate > tier limit |
| `seldon_errors_total{tenant}` | Counter | > 10/min |
| `postgres_connections{schema}` | Gauge | > 80% of pool |
| `pod_memory_usage{tenant}` | Gauge | > 90% of limit |

**Logging:**
- Loki for log aggregation
- Logs tagged with `tenant_id`
- Retention: 7 days (30 days for Enterprise)

**Tracing:**
- Optional (Phase 2): OpenTelemetry + Tempo
- Trace requests across agent handoffs

---

## 9. Security Model

### 9.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| **Tenant A accesses Tenant B's data** | Schema isolation + JWT verification + RLS policies |
| **Tenant escapes container** | Read-only root filesystem, no privileged containers, AppArmor |
| **Tenant exhausts cluster resources** | Resource quotas, rate limiting, circuit breakers |
| **Compromised API key** | Key rotation, scoped permissions, IP allowlisting (Enterprise) |
| **Discord bot abuse** | Per-tenant bot tokens, Discord rate limits, anomaly detection |
| **SQL injection** | Prepared statements, ORM (Prisma), schema validation |
| **Secrets exposure** | k8s Secrets (encrypted at rest), RBAC, secret rotation |

### 9.2 Network Policies

**Kubernetes NetworkPolicies:**

```yaml
# Tenant pod can only talk to database and external APIs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-pod-policy
spec:
  podSelector:
    matchLabels:
      app: seldon
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: traefik  # Ingress controller
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    - to:  # External APIs (Anthropic, Discord, etc.)
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8  # No access to private networks
      ports:
        - protocol: TCP
          port: 443
```

### 9.3 Secrets Management

**k8s Secrets (encrypted at rest):**
- Enable encryption at rest in kube-apiserver
- Use external secrets operator (sync from 1Password/Vault)

**Rotation Policy:**
- Database passwords: Rotate every 90 days
- API keys: Rotate on demand (tenant-initiated)
- JWT secret: Rotate every 365 days (requires re-login)

### 9.4 Compliance

**GDPR:**
- Data residency: Hetzner Germany (Frankfurt datacenter)
- Right to deletion: API endpoint to purge tenant schema
- Data export: API endpoint to download all tenant data as JSON

**SOC 2 (Phase 2):**
- Access logging (audit trail in auth_db)
- Encryption in transit (TLS 1.3)
- Encryption at rest (PostgreSQL + k8s secrets)
- Regular security audits

---

## 10. Migration Path

### 10.1 Code Changes Required

**Seldon Protocol (seldon-protocol/):**

1. **Add tenant context to all database queries**
   ```typescript
   // Before (single-tenant)
   const tasks = await db.tasks.findMany();

   // After (multi-tenant)
   const tasks = await db.tasks.findMany({
     where: { tenant_id: req.tenant.id }
   });
   
   // Or use schema prefix
   await db.raw(`SET search_path TO tenant_${tenantSlug}, public`);
   ```

2. **Add JWT middleware**
   ```typescript
   app.use('/api', verifyJWT);
   app.use('/api', attachTenantContext);
   ```

3. **Add tier enforcement middleware**
   ```typescript
   app.use('/seldon/dispatch', enforceTierLimits);
   ```

4. **Update Discord client initialization**
   ```typescript
   // Before (global bot token)
   const discord = new DiscordClient(process.env.DISCORD_BOT_TOKEN);

   // After (per-tenant bot token)
   const discord = new DiscordClient(req.tenant.discord_bot_token);
   ```

**Dashboard (dashboard/):**

1. **Add subdomain routing**
   ```typescript
   const tenantSlug = req.hostname.split('.')[0];
   const apiUrl = `http://seldon-${tenantSlug}:18789`;
   ```

2. **Add login page**
   ```typescript
   // New route: /login
   // Authenticate against auth_db, issue JWT
   ```

**Database (init-scripts/):**

1. **Create auth_db schema**
   ```sql
   -- init-scripts/00-auth-db.sql
   CREATE DATABASE auth_db;
   \c auth_db;
   -- (tenants, users, api_keys tables)
   ```

2. **Update migration scripts to be tenant-aware**
   ```bash
   # scripts/migrate-tenant.sh
   psql -c "SET search_path TO tenant_$1; \i $2"
   ```

### 10.2 New Services Required

**Auth Service:**
- Handles login, signup, JWT issuance
- Tech: Node.js/Express, bcrypt, jsonwebtoken
- Endpoints: `/auth/login`, `/auth/signup`, `/auth/refresh`

**Provisioning Service:**
- Creates tenant schema, ConfigMaps, k8s deployments
- Tech: Node.js + Kubernetes client library
- Triggered by: Signup webhook, tier upgrade event

**Billing Service:**
- Syncs usage events to Stripe
- Handles webhooks (subscription.created, payment.failed)
- Tech: Node.js/Express + Stripe SDK

**Admin Dashboard:**
- Internal tool for ops team
- View all tenants, usage, health
- Manually provision/deprovision tenants
- Tech: React + TailwindCSS, talks to auth_db

### 10.3 Infrastructure Setup

**Phase 1: Hetzner Kubernetes Cluster**
```bash
# 1. Create Hetzner Cloud project
hcloud project create foundation-prod

# 2. Create k8s cluster via Terraform
terraform init
terraform apply -var-file=prod.tfvars

# 3. Install base components
kubectl apply -f infra/traefik/
kubectl apply -f infra/cert-manager/
kubectl apply -f infra/prometheus/
```

**Phase 2: Deploy PostgreSQL**
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql-ha \
  --set postgresql.database=auth_db \
  --set postgresql.replicaCount=2 \
  --set pgpool.replicaCount=1
```

**Phase 3: Deploy Auth + Provisioning Services**
```bash
kubectl apply -f k8s/auth-service.yaml
kubectl apply -f k8s/provisioning-service.yaml
kubectl apply -f k8s/billing-service.yaml
```

**Phase 4: Deploy First Tenant (Alpha)**
```bash
./scripts/provision-tenant.sh alpha starter
# Verify: curl https://alpha.foundationcloud.dev/health
```

### 10.4 Testing Strategy

**Local Multi-Tenant Testing:**
1. Use Minikube or Kind (local k8s)
2. Deploy 3 test tenants (alice, bob, charlie)
3. Run integration tests:
   - Alice cannot read Bob's tasks
   - Rate limits enforced per tenant
   - Discord threads isolated per tenant

**Staging Environment:**
- Hetzner staging cluster (smaller nodes)
- Real Stripe test mode
- Real Discord bot (test guild)
- Load test: Simulate 50 tenants, 10 tasks/min each

---

## 11. Phase Plan

### Phase 0: Foundation (Week 1-2)

**Goal:** Set up infrastructure and auth layer

- [ ] Create Hetzner k8s cluster (Terraform)
- [ ] Deploy PostgreSQL cluster (Patroni HA)
- [ ] Create auth_db schema (tenants, users, api_keys, usage_events)
- [ ] Build Auth Service (login, signup, JWT)
- [ ] Set up Traefik ingress with wildcard SSL
- [ ] Deploy monitoring stack (Prometheus + Grafana)

**Success Criteria:**
- Can create test tenant via API
- JWT auth works end-to-end
- Metrics visible in Grafana

### Phase 1: Starter Tier MVP (Week 3-6)

**Goal:** Launch limited public beta (Starter tier only)

- [ ] Multi-tenant Seldon Protocol (tenant context in all queries)
- [ ] Schema-per-tenant provisioning
- [ ] Discord OAuth2 onboarding flow
- [ ] 5-agent configuration for Starter tier
- [ ] Dashboard with login page
- [ ] Stripe subscription setup (manual provisioning)
- [ ] Rate limiting (60 req/min, 500 tasks/month)
- [ ] Documentation: Getting Started guide

**Success Criteria:**
- 10 beta customers onboarded
- Zero data leaks between tenants
- 99% uptime over 30 days
- Sub-2s task dispatch latency

**Launch Plan:**
1. Invite 10 beta users from mailing list
2. Collect feedback via Discord
3. Fix critical bugs (1 week buffer)

### Phase 2: Pro Tier + Billing (Week 7-10)

**Goal:** Enable self-service signup and upgrades

- [ ] All 14 agents enabled for Pro tier
- [ ] Stripe metered billing (overage charges)
- [ ] Usage dashboard (real-time task count)
- [ ] Tier enforcement (concurrent tasks, workflow limits)
- [ ] Upgrade/downgrade flow
- [ ] API key management (create, rotate, revoke)
- [ ] Email notifications (quota warnings, payment failures)

**Success Criteria:**
- 50 paying customers (mix of Starter + Pro)
- Automated billing works (no manual intervention)
- Churn rate < 10% in first month

### Phase 3: Scale + Enterprise (Week 11-14)

**Goal:** Support 100+ tenants, launch Enterprise tier

- [ ] Horizontal autoscaling (per tenant pods)
- [ ] Cluster autoscaler (add nodes on demand)
- [ ] Enterprise tier (dedicated nodes, custom agents)
- [ ] BYOK (bring your own Anthropic key)
- [ ] IP allowlisting (Enterprise security)
- [ ] Custom domain support (acme.example.com → CNAME)
- [ ] SLA monitoring (uptime, latency)
- [ ] Sales team onboarding (demo environment)

**Success Criteria:**
- 100 total customers
- 5 Enterprise deals closed
- 99.9% uptime
- Support ticket response time < 4 hours

### Phase 4: Optimization (Week 15-18)

**Goal:** Reduce costs, improve reliability

- [ ] Database query optimization (indexes, connection pooling)
- [ ] Agent model routing (overflow to cheaper models)
- [ ] Caching layer (Redis for frequently accessed data)
- [ ] Log aggregation tuning (reduce Loki storage costs)
- [ ] Anomaly detection (detect abusive tenants)
- [ ] Runbook for common incidents
- [ ] SOC 2 audit preparation

**Success Criteria:**
- COGS < $25 per Pro tenant per month
- p99 latency < 5s for task dispatch
- Zero critical incidents in 30 days

---

## 12. Cost Analysis

### 12.1 Infrastructure Costs (Month 1)

| Item | Provider | Cost |
|------|----------|------|
| K8s nodes (3x CPX51) | Hetzner | €180 |
| Database node (CPX31) | Hetzner | €45 |
| Infra node (CPX21) | Hetzner | €20 |
| Load balancer | Hetzner | €5 |
| Object storage (backups) | Hetzner | €5 |
| **Total Infrastructure** | | **€255/mo** |

### 12.2 API Costs (100 tenants)

**Pooled Model (Anthropic Max):**
- 5x Anthropic Max subscriptions @ $100/mo = $500/mo
- Supports 100 Starter tenants (avg 10 tasks/day, 5 agents)

**BYOK Model (Tenants provide keys):**
- No API costs to OpenClaw
- Tenants pay Anthropic directly

### 12.3 Revenue Projections

**Target Mix (100 tenants):**
- 70 Starter @ $49/mo = $3,430/mo
- 25 Pro @ $149/mo = $3,725/mo
- 5 Enterprise @ $500/mo = $2,500/mo
- **Total MRR:** $9,655/mo

**Costs:**
- Infrastructure: €255/mo (~$270/mo)
- Anthropic API (pooled): $500/mo
- Stripe fees (2.9% + $0.30): ~$300/mo
- Support/ops (part-time): $2,000/mo
- **Total COGS:** $3,070/mo

**Gross Margin:** $9,655 - $3,070 = **$6,585/mo (68%)**

### 12.4 Break-Even Analysis

**Fixed Costs:** $2,770/mo (infra + Anthropic + Stripe)

**Break-even customers:**
- Starter only: $2,770 / $49 = 57 customers
- Pro only: $2,770 / $149 = 19 customers
- Mixed (realistic): ~35 customers (25 Starter + 10 Pro)

**Time to Break-Even:**
- Phase 1 (beta): 10 customers = -$2,280/mo (investment phase)
- Phase 2 (launch): 50 customers = +$450/mo (break-even)
- Phase 3 (scale): 100 customers = +$6,585/mo (profitable)

**Estimated Timeline:** Break-even at Month 4 (assuming 10 new customers/month)

---

## Appendices

### A. API Endpoint Reference

```
Auth Service (auth.foundationcloud.dev)
POST   /auth/signup              # Create new tenant
POST   /auth/login               # Get JWT
POST   /auth/refresh             # Refresh JWT
POST   /auth/password-reset      # Reset password

Tenant API ({tenant}.foundationcloud.dev/api)
GET    /seldon/status            # System status
GET    /seldon/tasks             # List tasks
POST   /seldon/dispatch          # Create task
GET    /billing/usage            # Usage this month
GET    /billing/invoices         # Past invoices

Admin API (admin.foundationcloud.dev)
GET    /admin/tenants            # List all tenants
POST   /admin/tenants/:id/suspend # Suspend tenant
GET    /admin/metrics            # Aggregate metrics
```

### B. Database Schema (auth_db)

```sql
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug VARCHAR(50) UNIQUE NOT NULL,
  tier VARCHAR(20) NOT NULL, -- starter, pro, enterprise
  status VARCHAR(20) DEFAULT 'active', -- active, suspended, inactive
  stripe_customer_id VARCHAR(100),
  stripe_subscription_id VARCHAR(100),
  discord_bot_token TEXT,
  discord_guild_id VARCHAR(100),
  anthropic_api_key TEXT, -- nullable (BYOK)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role VARCHAR(20) DEFAULT 'member', -- admin, member
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL, -- bcrypt hash of key
  name VARCHAR(100),
  scopes TEXT[] DEFAULT '{}',
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE usage_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  event_type VARCHAR(50) NOT NULL, -- task.dispatched, workflow.started
  quantity INTEGER DEFAULT 1,
  metadata JSONB DEFAULT '{}'::jsonb,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_usage_tenant_type ON usage_events(tenant_id, event_type);
CREATE INDEX idx_usage_timestamp ON usage_events(timestamp DESC);
```

### C. Kubernetes Deployment Template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seldon-{{TENANT_SLUG}}
  namespace: foundation
  labels:
    app: seldon
    tenant: {{TENANT_SLUG}}
    tier: {{TIER}}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seldon
      tenant: {{TENANT_SLUG}}
  template:
    metadata:
      labels:
        app: seldon
        tenant: {{TENANT_SLUG}}
    spec:
      containers:
        - name: seldon
          image: ghcr.io/foundation/seldon:v2.0
          ports:
            - containerPort: 18789
              name: api
          env:
            - name: DB_HOST
              value: postgres-pgpool
            - name: DB_SCHEMA
              value: tenant_{{TENANT_SLUG}}
            - name: TENANT_SLUG
              value: {{TENANT_SLUG}}
            - name: TIER
              value: {{TIER}}
          envFrom:
            - secretRef:
                name: tenant-secrets-{{TENANT_SLUG}}
          volumeMounts:
            - name: config
              mountPath: /app/config
          resources:
            requests:
              cpu: {{CPU_REQUEST}}
              memory: {{MEMORY_REQUEST}}
            limits:
              cpu: {{CPU_LIMIT}}
              memory: {{MEMORY_LIMIT}}
          livenessProbe:
            httpGet:
              path: /health
              port: 18789
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 18789
            initialDelaySeconds: 10
            periodSeconds: 5
        - name: dashboard
          image: ghcr.io/foundation/dashboard:v2.0
          ports:
            - containerPort: 18810
              name: http
          env:
            - name: SELDON_HOST
              value: localhost
            - name: SELDON_PORT
              value: "18789"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 512Mi
      volumes:
        - name: config
          configMap:
            name: agents-config-{{TENANT_SLUG}}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
---
apiVersion: v1
kind: Service
metadata:
  name: seldon-{{TENANT_SLUG}}
  namespace: foundation
spec:
  selector:
    app: seldon
    tenant: {{TENANT_SLUG}}
  ports:
    - name: api
      port: 18789
      targetPort: 18789
    - name: dashboard
      port: 18810
      targetPort: 18810
```

### D. Monitoring Dashboards

**Grafana Dashboard: Tenant Overview**

```
Panels:
- Active Tenants (gauge)
- Tasks Dispatched Today (counter)
- API Request Rate (graph per tenant)
- Error Rate (graph per tenant)
- Task Duration p95 (heatmap)
- Concurrent Tasks (graph per tenant)
- Resource Usage (CPU/memory per tenant)
```

**Prometheus Alerts:**

```yaml
groups:
  - name: tenant_alerts
    rules:
      - alert: TenantHighErrorRate
        expr: rate(seldon_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate for tenant {{ $labels.tenant }}"
          
      - alert: TenantResourceExhaustion
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Tenant {{ $labels.tenant }} using >90% memory"
```

---

## Conclusion

This architecture balances pragmatism with scalability. The hybrid isolation model provides strong tenant boundaries without excessive infrastructure costs. Schema-per-tenant PostgreSQL is battle-tested in production SaaS (GitLab, Heroku Postgres, Citus).

**Next Steps:**
1. Review this document with engineering team
2. Create Terraform modules for infrastructure
3. Build Auth Service (Week 1-2)
4. Deploy staging environment (Week 3)
5. Begin Phase 1 implementation

**Open Questions:**
- Should we offer Europe + US regions (GDPR vs latency)?
- Do we need GraphQL API for dashboard (vs REST)?
- Should Enterprise tier get dedicated database instances?

**Decision Log:**
- 2026-02-03: Initial architecture designed (hybrid isolation model selected)
